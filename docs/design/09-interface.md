# KERTO — Interface Design

## ADR-009: Level 4 Interface — The Agent-Facing API

**Status:** Proposed
**Context:** Levels 0-3 are built: pure graph domain, ingestion + rendering, stateful engine, mesh primitives. Nothing talks to them from the outside. Level 4 is where Kerto becomes a product — the surface that agents and developers touch.

## The Problem

We have:
- `Engine.ingest/2` — but nothing feeds it occurrences
- `Engine.get_node/3` — but nothing asks for nodes
- `Rendering.Query.query_context/5` — but nothing triggers queries
- `Rendering.Renderer.render/1` — but nothing prints the output

297 tests pass. Zero users can use the system. Level 4 closes this gap.

## Design Philosophy

### 1. Commands Are the API, Transports Are Plumbing

The mistake most CLIs make: coupling arg parsing with business logic. Instead:

```
Transport (CLI, MCP, Socket)     — parses input, formats output
         ↓                ↑
Command Layer               — the real API
         ↓                ↑
Engine (Level 2)            — the stateful core
```

Every command is a function: `execute(engine, args) → {:ok, data} | {:error, reason}`. No IO. No formatting. No arg parsing. The same command works from CLI, MCP, Unix socket, or ExUnit tests.

### 2. Domain Verbs, Not CRUD

The API speaks the ubiquitous language:

| Domain Concept | Command | NOT |
|---------------|---------|-----|
| Querying context | `kerto context` | `kerto get-node` |
| Recording knowledge | `kerto learn` | `kerto create-learning` |
| Recording decisions | `kerto decide` | `kerto insert-decision` |
| Counter-evidence | `kerto weaken` | `kerto update-relationship` |
| Removing knowledge | `kerto delete` | `kerto remove` |
| Ingesting events | `kerto ingest` | `kerto import` |

### 3. Stdout Is Data, Stderr Is Messages

```bash
# Human reads stderr, machine reads stdout
kerto context auth.go                        # Pretty text to stdout
kerto context auth.go --json                 # JSON to stdout
kerto context auth.go --json 2>/dev/null     # Pure machine consumption
kerto context auth.go 2>&1                   # Human sees everything
```

Informational messages (warnings, hints) go to stderr. Data goes to stdout. This makes piping work naturally.

### 4. Progressive Disclosure

Simple things are simple. Complex things are possible.

```bash
# Simple (everything defaulted)
kerto context auth.go

# Full control
kerto context auth.go --kind file --depth 3 --min-weight 0.2 --json
```

### 5. No Daemon for Phase 1

The daemon + Unix socket architecture (02-architecture.md) is the goal, but it requires persistence. Phase 1: the CLI starts the OTP app, hydrates from snapshot (if available), runs the command, snapshots, exits. Still useful. Still fast (BEAM boots in ~100ms).

Daemon mode comes with persistence (future ADR).

## The Command Protocol

### Response Type

Every command returns the same type:

```elixir
defmodule Kerto.Interface.Response do
  @enforce_keys [:ok]
  defstruct [:ok, :data, :error]

  @type t :: %__MODULE__{
    ok: boolean(),
    data: term(),
    error: term()
  }

  @spec success(term()) :: t()
  def success(data), do: %__MODULE__{ok: true, data: data}

  @spec error(term()) :: t()
  def error(reason), do: %__MODULE__{ok: false, error: reason}
end
```

### Command Behaviour

```elixir
defmodule Kerto.Interface.Command do
  @type args :: %{atom() => term()}
  @type engine :: atom() | pid()

  @callback execute(engine(), args()) :: Response.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
end
```

### Dispatcher

```elixir
defmodule Kerto.Interface.Dispatcher do
  @commands %{
    "status"  => Command.Status,
    "context" => Command.Context,
    "learn"   => Command.Learn,
    "decide"  => Command.Decide,
    "ingest"  => Command.Ingest,
    "graph"   => Command.Graph,
    "decay"   => Command.Decay,
    "weaken"  => Command.Weaken,
    "delete"  => Command.Delete
  }

  @spec dispatch(String.t(), engine(), args()) :: Response.t()
  def dispatch(command_name, engine, args)
end
```

No `case` statement with 15 clauses. A map lookup. Adding a new command = adding one line to the map + one module.

## Command Reference

### `kerto status`

**What:** Graph health at a glance.

```bash
$ kerto status
Kerto Knowledge Graph
  Nodes:          42
  Relationships:  87
  Occurrences:    156
```

**Args:** None.
**Returns:**
```elixir
%{nodes: 42, relationships: 87, occurrences: 156}
```

---

### `kerto context <name>`

**What:** Everything Kerto knows about an entity, rendered for an agent.

```bash
$ kerto context auth.go
auth.go (file) — relevance 0.82, observed 12 times

Caution:
  breaks login_test.go (weight 0.87, 5 observations)
    "CI failure: auth.go changed, login_test failed"

Knowledge:
  decided JWT (weight 0.92, 2 observations)
    "Use JWT over sessions — stateless requirement"

Structure:
  often_changes_with auth_test.go (weight 0.65, 8 observations)
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `<name>` (positional) | required | Entity name |
| `--kind` | `:file` | Node kind (file, module, pattern, decision, error, concept) |
| `--depth` | `2` | BFS traversal depth |
| `--min-weight` | `0.0` | Minimum relationship weight to include |
| `--json` | `false` | JSON output |

**Pipeline:** `Identity.compute_id/2` → `Engine.get_graph/1` → `Query.query_context/5` → `Renderer.render/1`

**Returns:** Rendered text string or structured Context.

---

### `kerto learn <evidence>`

**What:** Agent records a learning. Creates a `context.learning` occurrence.

```bash
$ kerto learn --subject auth.go --relation caused_by --target "unbounded cache" \
    "auth.go OOM was caused by unbounded cache"
ok

$ kerto learn --subject parser.go "parser has quadratic complexity"
ok
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `<evidence>` (positional) | required | Evidence text (what was learned) |
| `--subject` | required | Subject entity name |
| `--subject-kind` | `:file` | Subject node kind |
| `--relation` | `:learned` | Relationship type |
| `--target` | `nil` | Target entity name (optional for single-node learnings) |
| `--target-kind` | `:concept` | Target node kind |
| `--confidence` | `0.8` | Confidence level (0.0-1.0) |

**Pipeline:** Construct `Occurrence{type: "context.learning"}` → `Engine.ingest/2`

When `--target` is omitted, only the subject node is upserted (no relationship created). This handles simple annotations like "parser.go has performance issues."

---

### `kerto decide <evidence>`

**What:** Record an architectural decision. Creates a `context.decision` occurrence.

```bash
$ kerto decide --subject auth --target JWT "stateless requirement, no sessions"
ok
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `<evidence>` (positional) | required | Decision rationale |
| `--subject` | required | What this decision is about |
| `--subject-kind` | `:module` | Subject node kind |
| `--target` | required | What was decided |
| `--target-kind` | `:decision` | Target node kind |
| `--confidence` | `0.9` | Confidence level |

**Pipeline:** Construct `Occurrence{type: "context.decision"}` → `Engine.ingest/2`

---

### `kerto ingest`

**What:** Pipe in a FALSE Protocol occurrence as JSON from stdin.

```bash
$ echo '{"type":"ci.run.failed","data":{"files":["auth.go"],"task":"test"},"source":{"system":"sykli","agent":"ci","ulid":"01JABC"}}' | kerto ingest
ok

$ cat occurrence.json | kerto ingest
ok
```

**Args:** None (reads JSON from stdin).

**Pipeline:** Parse JSON → Construct `Occurrence` + `Source` → `Engine.ingest/2`

This is the integration point for SYKLI, git hooks, and any external tool. The JSON schema matches `Occurrence.t()` directly.

---

### `kerto graph`

**What:** Dump the full knowledge graph.

```bash
$ kerto graph                    # JSON (default)
{"nodes": [...], "relationships": [...]}

$ kerto graph --format dot       # Graphviz DOT
digraph kerto {
  "auth.go" -> "login_test.go" [label="breaks (0.87)"];
}
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `--format` | `json` | Output format: `json`, `dot`, `text` |
| `--min-weight` | `0.0` | Minimum weight to include |

**Pipeline:** `Engine.get_graph/1` → serialize to requested format.

---

### `kerto decay`

**What:** Force a decay cycle. Useful for testing or after bulk ingestion.

```bash
$ kerto decay
Decay complete: 3 nodes pruned, 7 relationships pruned

$ kerto decay --factor 0.5       # Aggressive decay
Decay complete: 12 nodes pruned, 34 relationships pruned
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `--factor` | `0.95` (from Config) | Decay factor |

**Pipeline:** `Engine.decay/2`

---

### `kerto weaken`

**What:** Apply counter-evidence to a relationship. "This used to be true, but it's less true now."

```bash
$ kerto weaken --source auth.go --relation breaks --target login_test \
    --reason "Fixed in PR #42"
ok
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `--source` | required | Source entity name |
| `--source-kind` | `:file` | Source node kind |
| `--relation` | required | Relationship type |
| `--target` | required | Target entity name |
| `--target-kind` | `:file` | Target node kind |
| `--factor` | `0.5` | Weaken factor (0.0-1.0) |
| `--reason` | `nil` | Optional reason text |

**Pipeline:** Construct `{:weaken_relationship, ...}` → `Engine.Store.apply_ops/3`

Note: `weaken` is different from `delete`. Weakening reduces confidence — the knowledge fades naturally. Deleting is immediate removal. `ci.run.passed` uses weakening internally.

---

### `kerto delete`

**What:** Hard-remove a node or relationship from the graph.

```bash
# Delete a node and all its relationships
$ kerto delete --node auth.go --kind file
Deleted node auth.go and 5 relationships

# Delete a specific relationship
$ kerto delete --source auth.go --relation breaks --target login_test
Deleted relationship auth.go --breaks--> login_test
```

**Args:**

| Flag | Default | Description |
|------|---------|-------------|
| `--node` | `nil` | Node name to delete |
| `--kind` | `:file` | Node kind (for node deletion) |
| `--source` | `nil` | Source name (for relationship deletion) |
| `--source-kind` | `:file` | Source node kind |
| `--relation` | `nil` | Relationship type |
| `--target` | `nil` | Target name |
| `--target-kind` | `nil` | Target node kind |

Must provide either `--node` or all of `--source/--relation/--target`.

**Pipeline:** `Engine.delete_node/3` or `Engine.delete_relationship/5` (new Engine API).

---

## Output Contract

### JSON Mode (`--json` flag or MCP)

```json
{
  "ok": true,
  "data": { ... }
}
```

```json
{
  "ok": false,
  "error": "Node not found: auth.go (file)"
}
```

### Text Mode (default CLI)

Success: formatted human-readable output to stdout.
Error: error message to stderr, exit code 1.

### Serialization

Nodes serialize as:
```json
{
  "id": "a1b2c3...",
  "name": "auth.go",
  "kind": "file",
  "relevance": 0.82,
  "observations": 12,
  "first_seen": "01JABC...",
  "last_seen": "01JXYZ..."
}
```

Relationships serialize as:
```json
{
  "source": "a1b2c3...",
  "target": "d4e5f6...",
  "relation": "breaks",
  "weight": 0.87,
  "observations": 5,
  "evidence": ["CI failure: auth.go changed", "..."]
}
```

Atoms serialize as strings. ULIDs as strings. Floats as numbers.

## CLI Transport

### Escript Entry Point

```elixir
defmodule Kerto.Interface.CLI do
  @spec main([String.t()]) :: no_return()
  def main(args) do
    {command, parsed_args} = Parser.parse(args)

    Application.ensure_all_started(:kerto)

    response = Dispatcher.dispatch(command, :kerto_engine, parsed_args)

    format = if parsed_args[:json], do: :json, else: :text
    Output.print(response, format)

    if response.ok, do: System.halt(0), else: System.halt(1)
  end
end
```

### Arg Parser

```elixir
defmodule Kerto.Interface.Parser do
  @spec parse([String.t()]) :: {String.t(), map()}
  def parse(args)
end
```

Uses `OptionParser.parse!/2` with command-specific switch definitions. The parser knows which flags each command accepts — invalid flags are rejected early with helpful errors.

### Output Formatter

```elixir
defmodule Kerto.Interface.Output do
  @spec print(Response.t(), :text | :json) :: :ok
  def print(response, format)
end
```

Text mode: calls command-specific formatters. JSON mode: `Jason.encode!/1`.

### Error Messages

Errors are helpful, not cryptic:

```
$ kerto context
Error: missing entity name
Usage: kerto context <name> [--kind KIND] [--depth N]

$ kerto context auth.go
Entity not found: auth.go (file)
Hint: known files include auth_test.go, handler.go, parser.go

$ kerto learn "something"
Error: missing --subject flag
Usage: kerto learn <evidence> --subject NAME [--relation TYPE] [--target NAME]
```

The "Hint" with known entities uses a simple prefix/fuzzy match against the graph. Small detail, big UX.

## Application Supervisor

```elixir
defmodule Kerto.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Process groups for domain events (OTP built-in)
      {Kerto.PG, []},

      # Level 2: The stateful core
      {Kerto.Engine, name: :kerto_engine},

      # Future: Level 3 mesh
      # {Kerto.Mesh.Supervisor, []},

      # Future: Level 4 daemon
      # {Kerto.Interface.Socket, []},
      # {Kerto.Interface.ContextRenderer, []},
    ]

    opts = [strategy: :one_for_one, name: Kerto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Where `Kerto.PG` is a thin wrapper that starts the `:pg` scope:

```elixir
defmodule Kerto.PG do
  def child_spec(_opts) do
    %{id: __MODULE__, start: {:pg, :start_link, [:kerto]}}
  end
end
```

### Startup Sequence

```
1. :pg scope :kerto starts       — event pub/sub available
2. Kerto.Engine starts            — OccurrenceLog, Store, Decay
3. (future) Mesh.Supervisor       — Transport, Discovery, Peers
4. (future) Interface.Socket      — Unix socket listener
5. (future) ContextRenderer       — auto-render .kerto/CONTEXT.md
```

## ULID Generation

Commands that create occurrences (`learn`, `decide`, `ingest` from stdin without ULID) need ULID generation. A minimal implementation:

```elixir
defmodule Kerto.Interface.ULID do
  @crockford "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @spec generate() :: String.t()
  def generate do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(10)
    encode_timestamp(timestamp) <> encode_random(random)
  end
end
```

26 characters, time-sortable, monotonic within millisecond. Used only at the interface boundary — domain code receives ULIDs as strings.

## Module Layout

```
lib/kerto/
├── interface/
│   ├── cli.ex                    — Escript main, boots app, dispatches
│   ├── parser.ex                 — Arg parsing (OptionParser)
│   ├── output.ex                 — Text + JSON formatting
│   ├── dispatcher.ex             — Command name → module lookup
│   ├── response.ex               — Response struct
│   ├── ulid.ex                   — ULID generation
│   │
│   └── command/
│       ├── status.ex             — Graph statistics
│       ├── context.ex            — Query + render entity context
│       ├── learn.ex              — Record learning occurrence
│       ├── decide.ex             — Record decision occurrence
│       ├── ingest.ex             — Parse + ingest raw occurrence
│       ├── graph.ex              — Dump graph (JSON, DOT, text)
│       ├── decay.ex              — Force decay cycle
│       ├── weaken.ex             — Apply counter-evidence
│       └── delete.ex             — Hard-remove node/relationship
│
├── application.ex                — OTP application supervisor
└── pg.ex                         — :pg scope wrapper
```

## Engine API Additions

Level 4 needs two operations that Engine doesn't expose yet:

### `Engine.delete_node/3`
```elixir
@spec delete_node(atom(), atom(), String.t()) :: :ok | {:error, :not_found}
def delete_node(engine \\ __MODULE__, kind, name)
```
Removes the node and all relationships where it appears as source or target.

### `Engine.delete_relationship/5`
```elixir
@spec delete_relationship(atom(), atom(), String.t(), atom(), atom(), String.t()) :: :ok | {:error, :not_found}
def delete_relationship(engine \\ __MODULE__, source_kind, source_name, relation, target_kind, target_name)
```

These are added to Engine (Level 2) and Store (Level 2), not the Interface layer. The Interface just calls them.

### `Engine.context/4`

Convenience function that combines query + render:

```elixir
@spec context(atom(), atom(), String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found}
def context(engine \\ __MODULE__, kind, name, opts \\ []) do
  graph = get_graph(engine)
  case Rendering.Query.query_context(graph, kind, name, "", opts) do
    {:ok, ctx} -> {:ok, Rendering.Renderer.render(ctx)}
    error -> error
  end
end
```

## Implementation Order

### Phase 1: Command Layer (testable, no CLI yet)

Build order within Phase 1:

| # | Module | Tests | Notes |
|---|--------|-------|-------|
| 1 | `Response` | 4 | Pure struct, success/error constructors |
| 2 | `ULID` | 4 | Generation, format validation, monotonicity |
| 3 | `Command.Status` | 3 | Simplest command, validates pattern |
| 4 | `Command.Context` | 6 | Read path: query + render |
| 5 | `Command.Learn` | 6 | Write path: construct occurrence + ingest |
| 6 | `Command.Decide` | 4 | Write path, similar to Learn |
| 7 | `Command.Ingest` | 5 | JSON parsing + occurrence construction |
| 8 | `Command.Graph` | 5 | Serialization: JSON + DOT |
| 9 | `Command.Decay` | 3 | Thin wrapper around Engine.decay |
| 10 | `Command.Weaken` | 4 | Construct weaken op + apply |
| 11 | `Command.Delete` | 5 | Node deletion + relationship deletion |
| 12 | `Dispatcher` | 4 | Routing + unknown command handling |
| **Total** | | **~53** | |

All commands test against a real Engine (started via `start_supervised!`). No mocks. `async: false` for commands that write.

### Phase 2: CLI Transport

| # | Module | Tests | Notes |
|---|--------|-------|-------|
| 13 | `Parser` | 10 | All commands, edge cases, help text |
| 14 | `Output` | 8 | Text + JSON formatting for each response type |
| 15 | `CLI` | 6 | Integration: args → boot → dispatch → output |
| 16 | `Application` | 3 | Supervisor starts, Engine accessible |
| **Total** | | **~27** | |

### Phase 3: Daemon + MCP (future ADR)

- `Interface.Socket` — Unix domain socket listener
- `Interface.MCP` — MCP server (stdio mode)
- `Interface.ContextRenderer` — auto-renders `.kerto/CONTEXT.md` on graph changes
- Persistence (Engine.Persist) — snapshots + hydration

## Test Strategy

### Command Tests

Each command has its own test file. Tests start a real Engine and exercise the command:

```elixir
# test/interface/command/context_test.exs
defmodule Kerto.Interface.Command.ContextTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    engine = start_supervised!({Kerto.Engine, name: :test_cmd_engine, decay_interval_ms: :timer.hours(1)})
    # Seed some data
    occ = Occurrence.new("ci.run.failed", %{files: ["auth.go"], task: "test"}, Source.new("test", "agent", "01JABC"))
    Kerto.Engine.ingest(:test_cmd_engine, occ)
    %{engine: :test_cmd_engine}
  end

  test "returns rendered context for known entity", %{engine: engine} do
    response = Command.Context.execute(engine, %{name: "auth.go", kind: :file})
    assert response.ok
    assert response.data =~ "auth.go"
    assert response.data =~ "file"
  end

  test "returns error for unknown entity", %{engine: engine} do
    response = Command.Context.execute(engine, %{name: "nope.go", kind: :file})
    refute response.ok
    assert response.error == :not_found
  end
end
```

### CLI Integration Tests

Test the full pipeline: args → parse → dispatch → format:

```elixir
# test/interface/cli_test.exs
test "kerto status returns valid output" do
  assert {output, 0} = System.cmd("mix", ["run", "--no-halt", "-e", "Kerto.Interface.CLI.main([\"status\"])"])
  assert output =~ "Nodes:"
end
```

### What We DON'T Test

- OTP application startup in CI (flaky, process naming conflicts)
- Daemon mode (Phase 3)
- MCP protocol (Phase 3)

## Design Decisions

### D1: No HTTP Server

Kerto is a local tool. HTTP adds attack surface, port conflicts, and a dependency. Unix socket (Phase 3) gives the same connectivity with less exposure.

### D2: Commands Are Behaviours

Using `@callback` + `@behaviour` instead of bare functions. This:
- Makes the contract explicit (every command has name, description, execute)
- Enables the Dispatcher to validate at compile time
- Allows `kerto help` to auto-generate from module attributes

### D3: JSON Output via `--json` Flag, Not Content Negotiation

CLI tools that force JSON-by-default alienate humans. CLI tools that never output JSON alienate machines. The `--json` flag is the standard compromise (see: `gh`, `kubectl`, `docker`).

### D4: ULID at the Boundary

Domain code receives ULIDs as strings. Only the Interface layer generates them. This keeps Levels 0-3 pure — no `:crypto` dependency in domain code.

### D5: Engine Name Convention

All commands receive the Engine name (atom) as first argument. Default: `:kerto_engine`. Tests use unique names (`:test_cmd_engine`) for isolation. This matches the existing Engine/Store pattern.

### D6: No `kerto init` in Phase 1

`kerto init` creates `.kerto/`, configures MCP, installs git hooks. This requires persistence and daemon mode. Deferred to Phase 3. Phase 1 commands work against an ephemeral Engine (useful for testing, scripting, SYKLI integration).

## What This Unlocks

With Level 4 Phase 1:
- **SYKLI integration** — `sykli` can call `Kerto.Interface.Command.Ingest.execute/2` directly in the BEAM
- **Script integration** — `echo '...' | kerto ingest` works from any CI pipeline
- **Agent testing** — seed a graph, query context, verify output — all in ExUnit
- **Manual exploration** — developers can poke the graph from the terminal

With Phase 2 (CLI transport):
- **escript binary** — `mix escript.build` → standalone `kerto` binary
- **Agent usage** — Claude Code shells out to `kerto context auth.go`

With Phase 3 (daemon + MCP):
- **Zero-setup agents** — MCP auto-discovery, no CLAUDE.md needed
- **Persistent memory** — graph survives between sessions
- **Real-time CONTEXT.md** — any agent reads the file, gets project context

## Estimated Totals

| Phase | Modules | Tests | Lines (source) | Lines (test) |
|-------|---------|-------|----------------|--------------|
| Phase 1 | 12 | ~53 | ~400 | ~500 |
| Phase 2 | 4 | ~27 | ~250 | ~300 |
| **Total L4** | **16** | **~80** | **~650** | **~800** |

After Phase 1 + 2: **~377 tests** total (297 existing + 80 new).
