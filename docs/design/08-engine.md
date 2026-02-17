# KERTO — Engine Design

## ADR-008: Level 2 Engine — The Stateful Core

**Status:** Proposed
**Context:** Levels 0 and 1 are pure functions — they compute but don't remember. The Engine is where state lives. It owns ETS tables, runs timers, and provides the API that Level 3 (Mesh) and Level 4 (Interface) depend on.

## The Problem

We have:
- `Graph` (L0) — pure data structure, no persistence
- `Extraction` (L1) — returns `ExtractionOp` tuples, doesn't apply them
- `Rendering` (L1) — takes a `Graph.t()`, doesn't know where it comes from
- `Mesh.Sync` (L3) — needs an occurrence log for replay, doesn't have one

Nothing connects these. No process owns the graph. No process applies extraction ops. No process stores occurrences for mesh replay. The Engine is the missing runtime core.

## Design Principles

### From the BEAM Article

George Guimaraes' insight: agent orchestrators reinvent OTP badly. We're not going to do that. The Engine uses OTP the way it was meant to be used:

1. **ETS heir pattern** — graph survives process crashes without persistence
2. **One process per concern** — Store, Decay, OccurrenceLog are independent
3. **Supervision, not defensive coding** — happy path in GenServers, let the supervisor handle failures
4. **`:pg` process groups** — Engine publishes domain events to subscribers (mesh peers, context renderer)

### From Kerto's Architecture

- **Engine is a consumer of L0/L1** — calls `Graph.*`, `Extraction.*`, `Rendering.*` functions
- **Engine is a provider to L3/L4** — Mesh reads the occurrence log, Interface calls Engine API
- **Engine owns all mutable state** — ETS tables, timers, occurrence buffer
- **Engine emits domain events** — `OccurrenceIngested`, `DecayCycleCompleted` (defined in 01-ddd.md)

## Module Layout

```
lib/kerto/engine/
├── store.ex              — GenServer: owns ETS graph table, applies ops
├── occurrence_log.ex     — GenServer: owns ETS occurrence table, ring buffer
├── decay.ex              — GenServer: periodic decay timer
├── applier.ex            — Pure: ExtractionOp → Graph mutations (no process)
├── engine.ex             — Supervisor + public API facade
└── config.ex             — Runtime configuration (defaults + overrides)
```

## Module Details

### Engine.Config (pure, no process)

Runtime configuration with sensible defaults. Read from `.kerto/config.exs` if present, overridden by environment variables.

```elixir
defmodule Kerto.Engine.Config do
  @defaults %{
    ewma_alpha: 0.3,
    decay_factor: 0.95,
    decay_interval_ms: :timer.hours(6),
    death_threshold_edge: 0.05,
    death_threshold_node: 0.01,
    max_occurrences: 1024,
    snapshot_interval_ms: :timer.minutes(30)
  }

  @spec get(atom()) :: term()
  @spec defaults() :: map()
end
```

No GenServer — config is read at startup and passed to processes that need it. If config changes, restart the process (OTP way).

### Engine.Applier (pure, no process)

Bridges the gap between L1 extraction ops and L0 graph mutations. This is the function that ExtractionOp was designed for — it takes ops and a graph, returns a new graph.

```elixir
defmodule Kerto.Engine.Applier do
  @spec apply_ops(Graph.t(), [ExtractionOp.t()], String.t()) :: Graph.t()
  def apply_ops(graph, ops, ulid)
end
```

For each op:
- `{:upsert_node, %{kind, name, confidence}}` → `Identity.compute_id(kind, name)` → `Graph.upsert_node/5`
- `{:upsert_relationship, %{source_kind, source_name, relation, target_kind, target_name, confidence, evidence}}` → compute both IDs → `Graph.upsert_relationship/7`
- `{:weaken_relationship, %{source_kind, source_name, relation, target_kind, target_name, factor}}` → compute both IDs → find relationship → `Relationship.weaken/2` → update graph

This is a **pure function**. No ETS, no GenServer. Fully testable with Graph structs.

**Why separate from Store?** Keeps Store thin. Store serializes writes; Applier computes them. Different reasons to change.

### Engine.Store (GenServer)

Owns the ETS graph table. Serializes all writes. Exposes concurrent reads.

```elixir
defmodule Kerto.Engine.Store do
  use GenServer

  # --- Public API (called by anyone) ---

  @spec ingest(Occurrence.t()) :: :ok
  # Full pipeline: extract → apply → store

  @spec get_graph() :: Graph.t()
  # Reconstruct Graph.t() from ETS (for rendering, snapshots)

  @spec get_node(atom(), String.t()) :: {:ok, Node.t()} | :error
  # Lookup by kind + name

  @spec query_context(atom(), String.t(), keyword()) :: {:ok, Context.t()} | {:error, :not_found}
  # Convenience: subgraph + render in one call

  @spec decay(float()) :: :ok
  # Apply decay_all, called by Engine.Decay timer

  @spec apply_ops([ExtractionOp.t()], String.t()) :: :ok
  # Apply extraction ops (used by mesh replay — occurrence already in log)

  @spec dump() :: Graph.t()
  # Full graph for snapshots
end
```

**ETS Table: `:kerto_graph`**

```
Type: :named_table, :set, :public, read_concurrency: true
Heir: Engine supervisor pid

Key-Value pairs:
{:node, node_id}                        → Node.t()
{:rel, source_id, relation, target_id}  → Relationship.t()
```

`:public` + `read_concurrency: true` means any process reads without going through the GenServer. Only writes go through the GenServer (serialized). This is the BEAM way — reads scale to all cores, writes are serialized for consistency.

**ETS Heir Pattern:**

```elixir
def init(opts) do
  table = case :ets.whereis(:kerto_graph) do
    :undefined ->
      :ets.new(:kerto_graph, [
        :named_table, :set, :public,
        read_concurrency: true,
        {:heir, opts[:heir_pid], :kerto_graph}
      ])
    existing ->
      # Table survived a crash — reclaim it
      :ets.give_away(existing, self(), :reclaimed)
      existing
  end

  {:ok, %{table: table}}
end
```

If the Store process crashes, the supervisor inherits the ETS table. When Store restarts, it reclaims the table — no data loss, no re-hydration needed.

**Ingest Pipeline (inside GenServer):**

```
Occurrence arrives
  → Extraction.extract(occurrence) → [ExtractionOp.t()]
  → Applier.apply_ops(graph, ops, ulid) → new Graph.t()
  → Write changed nodes/relationships to ETS
  → Publish {:occurrence_ingested, occurrence, stats} via :pg
```

**Graph ↔ ETS Mapping:**

The Store does NOT keep `Graph.t()` as GenServer state. The graph lives in ETS. The Store reconstructs `Graph.t()` when needed (for `decay_all/2`, snapshots, subgraph queries) by reading ETS into a struct. At Kerto's scale (≤1000 nodes), this reconstruction is sub-millisecond.

Why not keep `Graph.t()` in GenServer state? Because ETS survives crashes (heir pattern). GenServer state doesn't.

### Engine.OccurrenceLog (GenServer)

Ring buffer of recent occurrences. Mesh sync replays from this log.

```elixir
defmodule Kerto.Engine.OccurrenceLog do
  use GenServer

  @spec append(Occurrence.t()) :: :ok
  # Add occurrence to log (FIFO eviction if full)

  @spec since(String.t() | nil) :: [Occurrence.t()]
  # All occurrences with ULID > sync_point (nil = all)

  @spec all() :: [Occurrence.t()]
  # All occurrences in order

  @spec count() :: non_neg_integer()
end
```

**ETS Table: `:kerto_occurrences`**

```
Type: :named_table, :ordered_set, :public, read_concurrency: true
Heir: Engine supervisor pid

Key: ulid :: String.t()
Value: Occurrence.t()
```

`:ordered_set` with ULID keys = automatically time-sorted. `since/1` is a single `:ets.select` with a key range — O(log n) not O(n).

**Ring Buffer Eviction:**

```elixir
def handle_cast({:append, occurrence}, state) do
  :ets.insert(:kerto_occurrences, {occurrence.source.ulid, occurrence})

  if :ets.info(:kerto_occurrences, :size) > state.max_occurrences do
    oldest_key = :ets.first(:kerto_occurrences)
    :ets.delete(:kerto_occurrences, oldest_key)
  end

  {:noreply, state}
end
```

**Why separate from Store?** Different lifecycle. Store evicts by decay (EWMA death). OccurrenceLog evicts by FIFO (oldest first). Different access patterns — Store is queried by node/relationship, OccurrenceLog is scanned by time range. And mesh sync needs the raw occurrences, not the graph.

### Engine.Decay (GenServer)

Periodic timer that triggers decay on the graph.

```elixir
defmodule Kerto.Engine.Decay do
  use GenServer

  # Sends :tick to itself every config.decay_interval_ms
  # On tick: calls Engine.Store.decay(config.decay_factor)
  # Publishes {:decay_completed, stats} via :pg
end
```

Thin process. Knows nothing about graphs or EWMA — just a timer that calls Store. If Decay crashes, it restarts and schedules the next tick. The graph is unaffected.

### Engine (Supervisor + Facade)

```elixir
defmodule Kerto.Engine do
  use Supervisor

  # --- Supervision Tree ---

  def init(opts) do
    children = [
      {Engine.OccurrenceLog, max: opts[:max_occurrences] || 1024},
      {Engine.Store, heir_pid: self()},
      {Engine.Decay, interval: opts[:decay_interval_ms], factor: opts[:decay_factor]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # --- Public Facade ---

  @spec ingest(Occurrence.t()) :: :ok
  def ingest(occurrence) do
    Engine.OccurrenceLog.append(occurrence)
    Engine.Store.ingest(occurrence)
  end

  @spec context(atom(), String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found}
  def context(kind, name, opts \\ [])

  @spec status() :: map()
  def status()
end
```

**Start order matters:**
1. `OccurrenceLog` first — Store.ingest writes to it
2. `Store` second — reads/writes the graph
3. `Decay` last — needs Store to be running

**`one_for_one`** — independent processes. Decay crash doesn't kill Store. OccurrenceLog crash doesn't kill Decay. ETS heir means table data survives any individual crash.

**The supervisor is the heir.** Both ETS tables use `{:heir, self()}` where `self()` is the Engine supervisor pid. When a child crashes, the supervisor receives `{:'ETS-TRANSFER', table, old_pid, data}` and holds the table until the restarted child reclaims it.

## Domain Events via `:pg`

Instead of custom pubsub, use OTP's built-in process groups:

```elixir
# Engine.Store publishes after ingest:
:pg.get_members(:kerto, :graph_events)
|> Enum.each(&send(&1, {:occurrence_ingested, occurrence, stats}))

# Mesh.Peer subscribes on connect:
:pg.join(:kerto, :graph_events, self())

# Future: ContextRenderer subscribes:
:pg.join(:kerto, :graph_events, self())
```

**Why `:pg` over GenEvent, Registry, or Phoenix.PubSub?**

| Option | Deps | Distributed? | Complexity |
|--------|------|-------------|-----------|
| `:pg` | Zero (OTP) | Yes (cross-node!) | Minimal |
| `Registry` | Zero (Elixir) | No | Low |
| `Phoenix.PubSub` | Phoenix dep | Yes | Medium |
| Custom GenServer | Zero | No | High |

`:pg` wins because it's zero-dependency AND works across BEAM nodes — which means mesh peers on remote nodes can subscribe to graph events. This is exactly the `Kerto.Mesh.Peer` use case.

## Data Flow

### Ingest Path (write)

```
Occurrence arrives (CLI, MCP, or Mesh)
│
├──→ Engine.OccurrenceLog.append(occurrence)
│    └── ETS :kerto_occurrences insert
│
└──→ Engine.Store.ingest(occurrence)
     ├── Extraction.extract(occurrence) → [ops]
     ├── Applier.apply_ops(graph, ops, ulid) → new_graph
     ├── ETS :kerto_graph writes (changed nodes/rels only)
     └── :pg publish {:occurrence_ingested, ...}
          ├── Mesh.Peer receives → forwards to remote peer
          └── (future) ContextRenderer receives → re-renders CONTEXT.md
```

### Query Path (read)

```
Agent asks for context (CLI, MCP)
│
└──→ Engine.context(:file, "auth.go", depth: 2)
     ├── Identity.compute_id(:file, "auth.go") → node_id
     ├── ETS :kerto_graph reads (direct, no GenServer)
     │   ├── {:node, node_id} → focal node
     │   └── {:rel, ...} → relationships (BFS traversal)
     ├── Build Graph.t() from collected data
     ├── Rendering.Query.query_context(graph, ...) → Context.t()
     └── Rendering.Renderer.render(context) → natural language string
```

Reads bypass the GenServer entirely — ETS `read_concurrency: true` means 10 agents query simultaneously with zero contention.

### Mesh Replay Path

```
Remote peer connects, sends sync_point
│
└──→ Engine.OccurrenceLog.since(sync_point)
     └── ETS :kerto_occurrences range scan → [Occurrence.t()]
          └── Mesh.Peer sends each to remote
```

### Decay Path

```
Timer fires (every 6h)
│
└──→ Engine.Decay :tick
     └── Engine.Store.decay(0.95)
          ├── Reconstruct Graph.t() from ETS
          ├── Graph.decay_all(graph, 0.95) → pruned_graph
          ├── Diff: find removed nodes/rels
          ├── ETS deletes for pruned, updates for surviving
          └── :pg publish {:decay_completed, stats}
```

## ETS Table Summary

| Table | Type | Keys | Heir | Purpose |
|-------|------|------|------|---------|
| `:kerto_graph` | `:set` | `{:node, id}`, `{:rel, src, rel, tgt}` | Engine supervisor | Knowledge graph |
| `:kerto_occurrences` | `:ordered_set` | `ulid` | Engine supervisor | Ring buffer for mesh sync |

Both tables: `:named_table`, `:public`, `read_concurrency: true`.

## Supervision Tree (Full)

```
Kerto.Application (one_for_one)
│
├── :pg scope :kerto
│   (started via :pg.start_link(:kerto))
│
├── Kerto.Engine (Supervisor, one_for_one)
│   │
│   ├── Engine.OccurrenceLog
│   │   (GenServer — owns :kerto_occurrences ETS)
│   │
│   ├── Engine.Store
│   │   (GenServer — owns :kerto_graph ETS, applies ops)
│   │
│   └── Engine.Decay
│       (GenServer — timer, calls Store.decay/1)
│
├── Kerto.Mesh.Supervisor (rest_for_one)  [Level 3, future]
│   └── ...
│
└── Kerto.Interface [Level 4, future]
    └── ...
```

## Test Strategy

### Pure modules (Engine.Applier, Engine.Config)

Standard ExUnit, `async: true`. No setup, no ETS.

```elixir
# test/engine/applier_test.exs
test "applies upsert_node op to empty graph" do
  graph = Graph.new()
  ops = [{:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}}]
  result = Applier.apply_ops(graph, ops, "01JABC")
  assert Graph.node_count(result) == 1
end
```

### GenServer modules (Store, OccurrenceLog, Decay)

Start processes in test setup. Use `start_supervised!/1` for automatic cleanup.

```elixir
# test/engine/store_test.exs
setup do
  # Start the full Engine supervisor so ETS heir works
  start_supervised!({Engine, []})
  :ok
end

test "ingest creates nodes in ETS" do
  occurrence = make_occurrence("ci.run.failed", %{files: ["a.go"], task: "test"})
  Engine.Store.ingest(occurrence)
  assert {:ok, _node} = Engine.Store.get_node(:file, "a.go")
end
```

### Estimated Test Counts

| Module | Tests | Notes |
|--------|-------|-------|
| Engine.Config | 6 | Defaults, override, env vars |
| Engine.Applier | 12 | All three op types, edge cases, multi-op sequences |
| Engine.Store | 18 | Ingest pipeline, reads, decay, ETS survival |
| Engine.OccurrenceLog | 10 | Append, since, ring buffer eviction, empty log |
| Engine.Decay | 6 | Timer fires, decay applied, stats published |
| Engine (integration) | 8 | Full pipeline, facade API, supervision |
| **Total** | **~60** | |

## Implementation Order

1. **Engine.Config** — pure, no deps, unlocks all other modules
2. **Engine.Applier** — pure, depends on L0/L1 only, heavily testable
3. **Engine.OccurrenceLog** — first GenServer, simple ETS ring buffer
4. **Engine.Store** — main GenServer, uses Applier, owns graph ETS
5. **Engine.Decay** — timer process, calls Store
6. **Engine** — supervisor + facade, wires 3-5 together, integration tests

## What This Unlocks

With Level 2 complete:

- **Mesh.Peer** (L3) can read `OccurrenceLog.since/1` for replay and subscribe to `:pg` events for live forwarding
- **CLI** (L4) can call `Engine.ingest/1`, `Engine.context/3`, `Engine.status/0`
- **MCP Server** (L4) can expose the same Engine API as tools
- **Persistence** (future Engine.Persist) can call `Engine.Store.dump/0` for snapshots
- **ContextRenderer** (future) can subscribe to `:pg` events and re-render `.kerto/CONTEXT.md`

The Engine is the hinge of the entire system. Everything below it is pure. Everything above it is interface.
