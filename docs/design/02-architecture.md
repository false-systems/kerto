# KERTO — Architecture

## ADR-001: System Architecture

**Status:** Accepted
**Context:** KERTO is a local knowledge graph for AI agents, built in Elixir on the BEAM. This ADR defines the component structure, dependency rules, OTP design, storage strategy, and interface design.

## Dependency Hierarchy

Four levels. Dependencies point inward. No exceptions.

```
Level 0: Graph (Core Domain)     — ZERO dependencies
Level 1: Ingestion + Rendering   — depends on Graph only
Level 2: Infrastructure          — depends on Graph (implements repository interfaces)
Level 3: Interface               — depends on all above (wires everything together)
```

### Level 0: `lib/kerto/graph/`

Pure domain logic. No GenServers, no ETS, no I/O, no side effects.

Modules:
- `Kerto.Graph.Node` — Knowledge Node struct + pure functions (observe, decay, dead?)
- `Kerto.Graph.Relationship` — Relationship struct + pure functions (reinforce, decay, dead?)
- `Kerto.Graph.NodeKind` — Value object, canonicalization rules
- `Kerto.Graph.RelationType` — Value object, relation categories
- `Kerto.Graph.EWMA` — Pure math (update, decay, death check)
- `Kerto.Graph.Identity` — Content-addressed ID computation (BLAKE2b)
- `Kerto.Graph` — Graph operations module: pure functions that take graph state in and return graph state out

**Rule:** No `import`, `alias`, or `require` of anything outside `Kerto.Graph.*`. No `:ets`, no `GenServer`, no `File`, no `IO`. These modules are testable with zero setup.

### Level 1: `lib/kerto/ingestion/` + `lib/kerto/rendering/`

Supporting contexts. Depend on Level 0 only.

Ingestion:
- `Kerto.Ingestion.Occurrence` — Occurrence struct
- `Kerto.Ingestion.Source` — Source value object
- `Kerto.Ingestion.Extraction` — Stateless: Occurrence → [{:node, attrs} | {:relationship, attrs}]
- `Kerto.Ingestion.Extractor.CiFailure` — Extracts from `ci.run.failed`
- `Kerto.Ingestion.Extractor.CiSuccess` — Extracts from `ci.run.passed`
- `Kerto.Ingestion.Extractor.Commit` — Extracts from `vcs.commit`
- `Kerto.Ingestion.Extractor.Learning` — Extracts from `context.learning`
- `Kerto.Ingestion.Extractor.Decision` — Extracts from `context.decision`

Rendering:
- `Kerto.Rendering.Context` — Context struct (what agents receive)
- `Kerto.Rendering.Renderer` — Stateless: graph state → natural language

**Rule:** May `alias Kerto.Graph.*`. May NOT alias `Kerto.Infrastructure.*` or `Kerto.Interface.*`.

### Level 2: `lib/kerto/infrastructure/`

ETS, disk I/O, timers. Implements the persistence and process management.

- `Kerto.Infrastructure.Store` — GenServer: owns ETS tables, serializes writes, exposes read API
- `Kerto.Infrastructure.Persist` — GenServer: periodic snapshots to ETF + JSON
- `Kerto.Infrastructure.RingBuffer` — Bounded occurrence storage (ETS-backed)
- `Kerto.Infrastructure.Decay` — GenServer: periodic decay tick
- `Kerto.Infrastructure.ULID` — Monotonic ULID generator

**Rule:** May alias Level 0 and Level 1. Implements repository behaviours defined by the domain. Owns all ETS tables.

### Level 3: `lib/kerto/interface/`

CLI, MCP, application entry point.

- `Kerto.Interface.CLI` — Escript entry point, command parsing
- `Kerto.Interface.CLI.Commands` — Individual command implementations
- `Kerto.Interface.MCP` — MCP server (future)
- `Kerto.Application` — OTP application, supervision tree

**Rule:** May alias anything. This is the wiring layer.

## OTP Supervision Tree

```
Kerto.Application (one_for_one)
│
├── Kerto.Infrastructure.ULID
│   (Agent — holds monotonic counter for ULID generation)
│
├── Kerto.Infrastructure.Store
│   (GenServer — creates and owns ETS tables)
│   Tables: :kerto_graph, :kerto_occurrences
│   On init: hydrates from warm ETF snapshot if available
│
├── Kerto.Infrastructure.Decay
│   (GenServer — sends :tick to itself every 6 hours)
│   On tick: reads all nodes/edges from Store, applies decay, writes back, prunes dead
│
├── Kerto.Infrastructure.Persist
│   (GenServer — sends :snapshot to itself every 30 minutes)
│   On snapshot: reads graph state from Store, writes ETF + JSON to .kerto/
│
├── Kerto.Infrastructure.ContextRenderer
│   (GenServer — re-renders .kerto/CONTEXT.md when graph changes)
│   Subscribes to domain events: OccurrenceIngested, DecayCycleCompleted, etc.
│
└── Kerto.Interface.Socket
    (GenServer — listens on .kerto/kerto.sock)
    Accepts CLI thin-client connections, dispatches to Store/Rendering
```

### Startup Sequence

1. `ULID` starts — ID generation available
2. `Store` starts — creates ETS tables, attempts hydration from `.kerto/graph.etf`
3. `Decay` starts — schedules first tick
4. `Persist` starts — schedules first snapshot
5. `ContextRenderer` starts — renders initial `.kerto/CONTEXT.md`
6. `Socket` starts — listens on `.kerto/kerto.sock` for CLI/MCP connections

### Crash Strategy

- `one_for_one` — processes are independent. If `Decay` crashes, `Store` keeps running.
- `Store` crash is serious (ETS tables die with the process). Mitigation: `:ets.new` with `heir` option pointing to `Application` pid — table survives process restart.
- `Persist` crash is non-critical — worst case, we miss one snapshot cycle.

### ETS Table Heir

```elixir
# Store creates tables with heir: application supervisor
:ets.new(:kerto_graph, [:named_table, :ordered_set, :public,
  read_concurrency: true,
  {:heir, self(), :kerto_graph}])

:ets.new(:kerto_occurrences, [:named_table, :ordered_set, :public,
  read_concurrency: true,
  {:heir, self(), :kerto_occurrences}])
```

If `Store` process dies, the supervisor inherits both tables. When `Store` restarts, it reclaims them via `GenServer.init/1` rather than recreating from scratch.

## ETS Table Schemas

Two tables. Logical separation lives in the Elixir modules, not in table sprawl. At KERTO's scale (1000 entities, 10MB cap), fewer tables means simpler snapshots, one heir instead of three, and atomic dumps.

### :kerto_graph (ordered_set)

```
Tagged-key design. All graph data in one table:

{:node, node_id}           → %Kerto.Graph.Node{...}
{:edge, source_id, relation, target_id} → %Kerto.Graph.Relationship{...}
{:name, name, kind}        → node_id :: String.t()
```

Node values:
```
%Kerto.Graph.Node{
  id: String.t(),
  name: String.t(),
  kind: atom(),
  relevance: float(),
  observations: non_neg_integer(),
  first_seen: String.t(),   # ULID
  last_seen: String.t(),    # ULID
  summary: String.t() | nil
}
```

Relationship values:
```
%Kerto.Graph.Relationship{
  source: String.t(),
  target: String.t(),
  relation: atom(),
  weight: float(),
  observations: non_neg_integer(),
  first_seen: String.t(),
  last_seen: String.t(),
  evidence: [String.t()]    # list of evidence texts (accumulates, not overwrites)
}
```

Ordered_set with tagged tuple keys enables efficient prefix scans:
- `{:edge, source_id, :_, :_}` finds all outgoing edges for a node
- `{:node, :_}` iterates all nodes
- `{:name, name, kind}` does name→ID lookup without a separate table

Reverse edge lookups (find all edges pointing TO a node) require a scan of `{:edge, :_, :_, target_id}`. At 1000 entities this is fast enough. If profiling shows otherwise, add a `:kerto_reverse` bag table later.

### :kerto_occurrences (ordered_set)

```
Key:   ulid :: String.t()
Value: %Kerto.Ingestion.Occurrence{...}
```

Ring buffer. ULID keys = time-sorted automatically. Max 1024 entries. Separate table because occurrences have different lifecycle (FIFO eviction) than graph data (EWMA decay).

## Persistence Strategy

### Three Tiers

| Tier | Format | Location | Purpose | Written |
|------|--------|----------|---------|---------|
| Hot | ETS | Memory | Active queries and writes | Always |
| Warm | ETF | `.kerto/graph.etf` | Fast hydration on restart | Every 30 min |
| Cold | JSON | `.kerto/graph.json` | Any tool can read (AI agents, scripts) | Every 30 min |

### Snapshot Process

Snapshots include a version byte prefix for forward compatibility. If you add a field to Node or Relationship, existing snapshots are still loadable — the version tells the hydration code whether to migrate.

```elixir
@snapshot_version 1

def handle_info(:snapshot, state) do
  graph_state = Kerto.Infrastructure.Store.dump()

  # Warm: ETF with version prefix (fast, BEAM-native)
  etf_binary = :erlang.term_to_binary(graph_state)
  File.write!(".kerto/graph.etf", <<@snapshot_version::8, etf_binary::binary>>)

  # Cold: JSON with version field (universal, agent-readable)
  json_state = to_json(graph_state) |> Map.put("_version", @snapshot_version)
  File.write!(".kerto/graph.json", Jason.encode!(json_state))

  schedule_snapshot()
  {:noreply, state}
end
```

### Hydration on Startup

```
1. Try .kerto/graph.etf (local cache):
   a. Read first byte as version
   b. If version == current → :erlang.binary_to_term(rest) → populate ETS
   c. If version < current → migrate(old_state) → populate ETS
   d. If corrupt or unreadable → fall through
2. If ETF missing/corrupt → try .kerto/graph.json (shared) → parse → check _version → populate
3. If both missing → start with empty graph
4. If org context configured → load org graph.json → merge as read-only base layer
```

### .kerto/ Directory Structure

```
.kerto/
├── graph.json             # Cold: JSON (shared via git — team knowledge)
├── graph.etf              # Warm: BEAM-native binary (.gitignore — local cache)
├── occurrences/           # Recent raw occurrences (.gitignore — ephemeral)
│   └── {ulid}.json
└── config.exs             # Optional: override defaults (committed — team config)
```

### Project Identity

KERTO is scoped to a single project directory (wherever `.kerto/` lives). The project is identified by the directory name by default, or overridden in `.kerto/config.exs`:

```elixir
# .kerto/config.exs (optional)
%{project: "my-project"}
```

When KERTO runs as a SYKLI plugin (Phase 2), SYKLI passes the project name from its own config. When KERTO emits `context.pattern` occurrences, the `context.project` field carries this identity. This is how AHTI knows which project a pattern belongs to.

A single KERTO instance serves one project. Multi-project setups require separate `.kerto/` directories (one per repo). This is deliberate — project graphs should not contaminate each other.

### Git-Shared Knowledge (Multi-Developer)

KERTO's knowledge is designed to be shared via git. The cold tier (JSON) is the shared artifact. The warm tier (ETF) is a local cache.

**What gets committed:**

```
.kerto/
├── graph.json             # ✅ Committed — shared team knowledge
├── graph.etf              # ❌ .gitignore — local cache, rebuilt from JSON
├── occurrences/           # ❌ .gitignore — ephemeral, per-developer
└── config.exs             # ✅ Committed — team-wide config overrides
```

**`.gitignore` entries:**

```
.kerto/graph.etf
.kerto/occurrences/
```

**Why this works:** Content-addressed identity (`blake2b(kind + canonical_name)`) guarantees that the same file or concept always produces the same node ID, regardless of which developer's agent learned it. Two developers learning about `auth.go` independently produce the same node — no conflicts.

**Merge strategy when two branches modify `graph.json`:**

Git will conflict on `graph.json` when two developers modify it on different branches. KERTO provides a merge driver:

```
# .gitattributes
.kerto/graph.json merge=kerto
```

```bash
# One-time setup (or in kerto init)
git config merge.kerto.driver "kerto merge-json %O %A %B"
```

The merge algorithm:

| Element | Strategy | Rationale |
|---------|----------|-----------|
| **Nodes** | Union. On conflict (same ID), take higher `relevance`, higher `observations`, later `last_seen` | Both developers observed the same thing — take the stronger signal |
| **Relationships** | Union. On conflict (same composite key), take higher `weight`, higher `observations`, concatenate `evidence` lists (deduplicated) | Evidence from both sides is valid |
| **Deleted nodes** | If one side deleted (decay pruned) and other side reinforced, keep the reinforced version | New evidence wins over decay |

This merge is lossless — no knowledge is discarded. The merged graph is always a superset of both branches. Worst case: a node that should have decayed survives a bit longer. This is safe because the next decay cycle will prune it anyway.

**Workflow:**

```
Developer A:  kerto learn "auth.go has OOM risk" → commit .kerto/graph.json
Developer B:  kerto learn "parser.go depends on auth.go" → commit .kerto/graph.json
git merge:    kerto merge-json produces union of both learnings
Result:       Both developers' agents now know both facts
```

### Org-Level Context (Multi-Repo)

Teams with multiple repos need shared knowledge that spans projects: architectural decisions, cross-repo dependencies, org-wide conventions. KERTO supports this via a read-only org overlay.

**Two-layer knowledge model:**

```
┌─────────────────────────────────────────────┐
│  Project Graph (read-write)                 │
│  .kerto/graph.json in each repo             │
│                                             │
│  "auth.go breaks login_test.go"             │
│  "parser.go has OOM risk"                   │
│  "cache must be bounded"                    │
└──────────────────┬──────────────────────────┘
                   │ merged at hydration
┌──────────────────▼──────────────────────────┐
│  Org Context (read-only overlay)            │
│  Separate repo or directory                 │
│                                             │
│  "We use JWT everywhere (stateless req)"    │
│  "Never use sessions — API gateway design"  │
│  "repo-a auth changes break repo-b tests"   │
└─────────────────────────────────────────────┘
```

**Setup:**

```elixir
# .kerto/config.exs
%{
  project: "my-service",
  org: "github.com/my-org/kerto-context"  # or local path
}
```

```bash
# Or via CLI
kerto init --org github.com/my-org/kerto-context
```

**How org context works:**

1. Org context lives in a dedicated repo (e.g., `my-org/kerto-context`) containing a `graph.json`
2. On hydration, KERTO loads project graph first, then merges org graph underneath
3. Org nodes and relationships are read-only — project agents cannot modify them
4. If a project reinforces an org-level node, the reinforcement stays in the project graph only
5. Org context is pulled on `kerto init` and refreshed periodically or on `kerto sync`

**Org context repo structure:**

```
kerto-context/
├── graph.json              # Org-wide knowledge graph
├── README.md               # What's in here and why
└── decisions/              # Optional: human-readable decision log
    ├── jwt-over-sessions.md
    └── no-orm.md
```

**Who writes to org context:**

- Maintainers commit directly (architectural decisions, org conventions)
- AHTI writes automatically (Phase 4 — detected cross-repo patterns flow down)
- KERTO never writes to org context — it only reads

**What this does NOT do:**

- No real-time sync between repos — org context is a snapshot, pulled periodically
- No automatic cross-repo pattern detection — that's AHTI's job (Phase 4)
- No centralized KERTO server — everything is files in git repos

This keeps KERTO fully local and git-native. The org overlay is just another JSON file loaded at startup. No new infrastructure, no servers, no accounts.

## Agent Interface

KERTO serves multiple AI agents concurrently. It runs as a daemon (long-lived BEAM process) with three interfaces — no HTTP, no network exposure.

### Daemon Architecture

```
Agent 1 (Claude Code) ──MCP────────┐
Agent 2 (Claude Code) ──MCP────────┤
Agent 3 (Ollama)      ──CLI────────┤──→ .kerto/kerto.sock ──→ KERTO daemon (BEAM)
Agent 4 (Cursor)      ──CLI────────┤    ├── ETS (concurrent reads)
Agent 5 (any)         ──file read──┘    ├── GenServer (serialized writes)
                                        └── auto-updates .kerto/CONTEXT.md
```

One BEAM process per project. Always running. Multiple agents connect simultaneously. The BEAM handles concurrency natively — 10 agents reading at once is free (ETS concurrent reads), 10 agents writing is serialized by the GenServer (evidence accumulates, no conflicts).

### Three Interfaces

| Interface | Who uses it | Integration effort | Capabilities |
|-----------|------------|-------------------|--------------|
| **MCP** | Claude Code, MCP-capable agents | Zero — auto-discovered | Full: query, learn, weaken, delete, graph |
| **CLI** | Ollama, any agent that shells out | Minimal — CLAUDE.md instruction | Full: all commands |
| **File** | Any agent, any tool | Zero — just read a file | Read-only: `.kerto/CONTEXT.md` |

### Interface 1: MCP Server (Primary)

KERTO runs as an MCP server over Unix socket (`.kerto/kerto.sock`). MCP-capable agents discover KERTO tools automatically.

**MCP Tools exposed:**

```json
{
  "tools": [
    {
      "name": "kerto_context",
      "description": "Get project context for a file or entity",
      "parameters": {"name": "string", "format": "string (text|json)"}
    },
    {
      "name": "kerto_learn",
      "description": "Record a learning about the project",
      "parameters": {
        "subject": "string", "subject_kind": "string",
        "relation": "string", "target": "string", "target_kind": "string",
        "description": "string", "confidence": "float"
      }
    },
    {
      "name": "kerto_decide",
      "description": "Record an architectural decision",
      "parameters": {"subject": "string", "target": "string", "description": "string"}
    },
    {
      "name": "kerto_weaken",
      "description": "Weaken an incorrect relationship",
      "parameters": {"source": "string", "relation": "string", "target": "string", "reason": "string"}
    },
    {
      "name": "kerto_graph",
      "description": "Get the full knowledge graph",
      "parameters": {"format": "string (json|dot)"}
    },
    {
      "name": "kerto_status",
      "description": "Get graph statistics",
      "parameters": {}
    }
  ]
}
```

**Agent setup (Claude Code):**

```json
// .mcp.json (in project root, or added by kerto init)
{
  "mcpServers": {
    "kerto": {
      "command": "kerto",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
```

With this, Claude Code automatically discovers all KERTO tools. No CLAUDE.md instructions needed — the agent *has* project memory as a native capability.

### Interface 2: CLI (Universal)

Thin client that connects to the daemon via Unix socket. If daemon isn't running, auto-starts it.

**Commands:**

```
kerto init                           # Initialize .kerto/, start daemon, configure MCP
kerto start                          # Start daemon (if not running)
kerto stop                           # Stop daemon
kerto context <name>                 # Query: natural language summary for an entity
kerto context --json <name>          # Query: structured JSON output
kerto learn <description>            # Write: agent records a learning
  --subject <name>                  # Required: what entity this is about
  --relation <type>                 # Optional: relationship type
  --target <name>                   # Optional: target entity
kerto decide <description>           # Write: record an architectural decision
  --subject <name>                  # Required: what this is about
  --target <name>                   # Required: what was decided
kerto graph                          # Dump: all nodes and edges (JSON)
kerto graph --dot                    # Dump: Graphviz DOT format
kerto status                         # Show: node count, edge count, disk usage, daemon status
kerto decay                          # Force: run decay cycle now
kerto ingest <file>                  # Ingest: a FALSE Protocol occurrence from file/stdin
kerto weaken <description>           # Weaken: reduce a relationship's weight
  --source <name>                    # Required: source entity
  --relation <type>                  # Required: relationship type
  --target <name>                    # Required: target entity
  --factor <float>                   # Optional: weaken factor (default: 0.5)
kerto delete                         # Delete: remove a node or relationship
  --node <name>                      # Delete a node (and all its relationships)
  --source <name> --relation <type> --target <name>  # Delete a specific relationship
kerto sync                           # Pull org context + refresh CONTEXT.md
```

**CLI Architecture:**

The CLI is a thin client. It connects to the daemon's Unix socket, sends the command, and prints the response. If the daemon isn't running, it starts it first.

```elixir
defmodule Kerto.Interface.CLI do
  def main(args) do
    {command, flags, rest} = parse(args)

    case command do
      "init"  -> Commands.Init.run(flags)  # Creates .kerto/, starts daemon
      "start" -> Commands.Start.run(flags) # Starts daemon
      "stop"  -> Commands.Stop.run(flags)  # Stops daemon
      "mcp"   -> Commands.MCP.run(flags)   # Starts MCP server mode (stdio)
      _       ->
        # All other commands: connect to daemon via socket
        ensure_daemon_running()
        response = send_to_daemon(command, flags, rest)
        print_response(response)
    end
  end
end
```

### Interface 3: File (Zero Integration)

The daemon maintains `.kerto/CONTEXT.md` — a rendered summary of the most relevant knowledge. Updated automatically whenever the graph changes.

**Example `.kerto/CONTEXT.md`:**

```markdown
# Project Context (auto-generated by KERTO)

## High Risk
- **src/auth.go** breaks login_test.go (87% confidence, seen 12 times)
- **src/parser.go** has OOM risk — unbounded cache (82% confidence)

## Decisions
- **auth module**: Use JWT over sessions — stateless requirement (95% confidence)
- **database**: PostgreSQL over MongoDB — relational data model (90% confidence)

## Patterns
- src/auth.go and src/auth_test.go often change together (78% confidence)
- Changes to src/handler.go trigger CI failures in integration tests (65% confidence)

## Recent Learnings
- parser.go cache must be bounded (learned 2 days ago)
- retry logic in client.go needs exponential backoff (learned 5 days ago)
```

**How agents use it:**

```markdown
# CLAUDE.md (added by kerto init)
Read .kerto/CONTEXT.md for project history and context before starting work.
```

Any agent that reads CLAUDE.md (or similar config files) gets project context automatically. No tool calls, no shell commands. Works with Ollama, Cursor, Claude Code, or any future agent.

**Update triggers:** CONTEXT.md is re-rendered when:
- A new occurrence is ingested
- A learning or decision is recorded
- A decay cycle completes (pruned knowledge removed from summary)
- A node or relationship is manually weakened/deleted

### What `kerto init` Does

```
1. Create .kerto/ directory
2. Create .kerto/config.exs with defaults
3. Add .kerto/graph.etf and .kerto/occurrences/ to .gitignore
4. Add .mcp.json with KERTO server config (if not present)
5. Add "Read .kerto/CONTEXT.md for project context" to CLAUDE.md (if present)
6. Install git hooks:
   - post-commit → kerto ingest (captures file co-changes)
7. Start the daemon
8. Generate initial CONTEXT.md (empty or from existing .kerto/graph.json)
```

### Output Contract

All CLI commands and MCP responses use the same JSON contract:

```json
{
  "ok": true,
  "data": { ... }
}
```

Or on error:

```json
{
  "ok": false,
  "error": "description"
}
```

Human-readable output goes to stderr. Machine-readable output goes to stdout. This lets agents pipe `kerto context auth.go` and parse JSON cleanly.

## Error Handling Strategy

### Philosophy

KERTO is a local tool. Errors are recoverable. Data loss is acceptable (the graph rebuilds from new evidence). No error should crash the CLI or require user intervention.

### Error Categories

| Category | Strategy | Example |
|----------|----------|---------|
| **Graph invariant violation** | Reject the operation, log, continue | Relevance out of bounds, duplicate node ID |
| **Extraction failure** | Skip the occurrence, log warning | Malformed SYKLI occurrence |
| **Persistence failure** | Log error, continue in-memory | Disk full, permission denied |
| **Hydration failure** | Start with empty graph, log warning | Corrupt ETF file |
| **CLI input error** | Print error to stderr, exit 1 | Unknown command, missing required flag |
| **ETS table error** | Let it crash — supervisor restarts | Table deleted externally |

### Elixir Error Patterns

```elixir
# Domain functions return tagged tuples
@spec upsert_node(map()) :: {:ok, Node.t()} | {:error, :invalid_kind | :name_empty}

# Infrastructure uses "let it crash" for unexpected errors
# Expected errors (disk full, corrupt file) return tagged tuples
@spec save_snapshot(map()) :: :ok | {:error, :write_failed}

# CLI catches all errors at the top level
def main(args) do
  case run(args) do
    {:ok, output} -> IO.puts(Jason.encode!(output)); System.halt(0)
    {:error, msg} -> IO.puts(:stderr, msg); System.halt(1)
  end
end
```

### No Exceptions for Control Flow

Domain and infrastructure code never raise for expected conditions. `raise` is reserved for programmer errors (bugs). `{:ok, _} | {:error, _}` for everything else.

## Configuration

### Defaults (No Config Required)

```elixir
# These are the defaults. Zero config needed.
@defaults %{
  ewma_alpha: 0.3,
  decay_factor: 0.95,
  decay_interval_ms: :timer.hours(6),
  death_threshold_edge: 0.05,
  death_threshold_node: 0.01,
  max_nodes: 1000,
  max_occurrences: 1024,
  snapshot_interval_ms: :timer.minutes(30),
  disk_budget_bytes: 10 * 1024 * 1024  # 10MB
}
```

### Override via Config File

Optional `.kerto/config.exs`:

```elixir
# Only override what you need
%{
  decay_interval_ms: :timer.hours(12),  # slower decay
  max_nodes: 500                         # tighter budget
}
```

### Override via Environment

```bash
KERTO_DECAY_INTERVAL_HOURS=12 kerto status
```

### Priority

```
Environment variable > .kerto/config.exs > defaults
```

## Build & Distribution

### Mix Project

```elixir
# mix.exs
defmodule Kerto.MixProject do
  use Mix.Project

  def project do
    [
      app: :kerto,
      version: "0.1.0",
      elixir: "~> 1.17",
      escript: [main_module: Kerto.Interface.CLI],
      deps: deps()
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},     # JSON encoding
      {:burrito, "~> 1.0"}    # Single binary packaging (optional)
    ]
  end
end
```

### Minimal Dependencies

- `jason` — JSON encoding/decoding (required for cold tier + CLI output)
- `burrito` — Single binary packaging (optional, for distribution)
- Everything else is Erlang/OTP stdlib (ETS, :crypto, :erlang)

### SYKLI Integration

When KERTO runs inside SYKLI's BEAM VM:

```elixir
# SYKLI's mix.exs includes KERTO as a dependency
{:kerto, path: "../kerto"}  # or {:kerto, "~> 0.1"}

# SYKLI's application.ex starts KERTO as a child
children = [
  # ... SYKLI's own children ...
  {Kerto.Application, []}
]
```

SYKLI writes directly to KERTO via Elixir function calls — no CLI, no JSON, no overhead:

```elixir
# In SYKLI's occurrence generation
Kerto.Infrastructure.Store.ingest(occurrence)
```

## File Layout (Complete)

```
kerto/
├── lib/
│   └── kerto/
│       ├── graph/                     # Level 0: Core Domain
│       │   ├── node.ex
│       │   ├── relationship.ex
│       │   ├── node_kind.ex
│       │   ├── relation_type.ex
│       │   ├── ewma.ex
│       │   ├── identity.ex
│       │   └── graph.ex
│       │
│       ├── ingestion/                 # Level 1: Supporting
│       │   ├── occurrence.ex
│       │   ├── source.ex
│       │   ├── extraction.ex
│       │   └── extractor/
│       │       ├── ci_failure.ex
│       │       ├── ci_success.ex
│       │       ├── commit.ex
│       │       ├── learning.ex
│       │       └── decision.ex
│       │
│       ├── rendering/                 # Level 1: Supporting
│       │   ├── context.ex
│       │   ├── renderer.ex
│       │   └── query.ex
│       │
│       ├── infrastructure/            # Level 2: Infrastructure
│       │   ├── store.ex
│       │   ├── persist.ex
│       │   ├── ring_buffer.ex
│       │   ├── decay.ex
│       │   ├── context_renderer.ex    # Auto-renders .kerto/CONTEXT.md
│       │   ├── ulid.ex
│       │   └── config.ex
│       │
│       ├── interface/                 # Level 3: Interface
│       │   ├── cli.ex                 # Thin client (connects to daemon)
│       │   ├── socket.ex              # Unix socket listener (.kerto/kerto.sock)
│       │   ├── mcp.ex                 # MCP server (stdio mode)
│       │   └── commands/
│       │       ├── init.ex
│       │       ├── start.ex
│       │       ├── stop.ex
│       │       ├── context.ex
│       │       ├── learn.ex
│       │       ├── decide.ex
│       │       ├── graph.ex
│       │       ├── status.ex
│       │       ├── decay.ex
│       │       ├── ingest.ex
│       │       ├── weaken.ex
│       │       ├── delete.ex
│       │       ├── sync.ex
│       │       └── help.ex
│       │
│       ├── events.ex
│       └── application.ex
│
├── test/
│   ├── graph/                         # Unit tests (pure, fast, no setup)
│   ├── ingestion/                     # Unit tests (pure extraction logic)
│   ├── rendering/                     # Unit tests (pure rendering)
│   ├── infrastructure/                # Integration tests (ETS, disk)
│   └── interface/                     # CLI integration tests
│
├── docs/
│   ├── concept.md
│   └── design/
│       ├── 01-ddd.md
│       ├── 02-architecture.md
│       └── ...
│
├── mix.exs
├── mix.lock
├── .formatter.exs
└── CLAUDE.md
