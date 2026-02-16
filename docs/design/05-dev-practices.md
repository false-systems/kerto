# KERTO — Development Practices

## Overview

Elixir code conventions specific to KERTO. These build on the general dev-practices skill, applied to a knowledge graph domain on the BEAM.

## Level 0: Pure Domain Code (Graph)

### The Purity Contract

Level 0 is **pure functional**. No side effects, no processes, no I/O. This is the most important rule in the codebase. Every function in `Kerto.Graph.*` takes data in, returns data out.

```elixir
# Good: pure function, takes struct, returns struct
@spec observe(Node.t(), float()) :: Node.t()
def observe(%Node{} = node, confidence) when confidence >= 0.0 and confidence <= 1.0 do
  new_relevance = EWMA.update(node.relevance, confidence)
  %{node | relevance: new_relevance, observations: node.observations + 1}
end

# Bad: side effect inside domain function
def observe(%Node{} = node, confidence) do
  Logger.info("observing node #{node.name}")  # NO — side effect
  ...
end
```

**Test for purity:** If the function can run in `async: true` tests with zero setup, it's pure. If it needs ETS, processes, or fixtures — it's not Level 0.

### Guard Clauses for Invariants

Use guards to enforce domain invariants at the function boundary. Let it crash on invalid input — callers are responsible for validation.

```elixir
@spec update(float(), float()) :: float()
def update(current, observation)
    when is_float(current) and is_float(observation)
    and current >= 0.0 and current <= 1.0
    and observation >= 0.0 and observation <= 1.0 do
  @alpha * observation + (1.0 - @alpha) * current
end

# Callers who pass bad data get MatchError — this is correct.
# Domain functions don't "handle" invalid input, they reject it.
```

### Struct Design

Every struct uses `@enforce_keys` for required fields. Optional fields have defaults.

```elixir
defmodule Kerto.Graph.Node do
  @enforce_keys [:id, :name, :kind]
  defstruct [
    :id,
    :name,
    :kind,
    relevance: 0.5,
    observations: 0,
    first_seen: nil,
    last_seen: nil,
    summary: nil
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    kind: atom(),
    relevance: float(),
    observations: non_neg_integer(),
    first_seen: String.t() | nil,
    last_seen: String.t() | nil,
    summary: String.t() | nil
  }
end
```

### Naming Conventions

Functions that transform a struct return the same type — no side effects implied:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `observe/2` | Reinforce with new evidence | `Node.observe(node, 0.8)` |
| `decay/2` | Apply time-based decay | `Node.decay(node, 0.95)` |
| `dead?/1` | Check death threshold | `Relationship.dead?(rel)` |
| `update/2` | EWMA math | `EWMA.update(current, observation)` |
| `compute_id/2` | Pure derivation from inputs | `Identity.compute_id(:file, "auth.go")` |
| `canonicalize/2` | Normalize name per kind | `Identity.canonicalize(:file, "./src/auth.go")` |

Functions that query or extract don't modify:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `extract/1` | Parse occurrence into graph elements | `Extraction.extract(occurrence)` |
| `render/2` | Produce natural language from graph | `Renderer.render(node, relationships)` |
| `subgraph/3` | Traverse and collect | `Graph.subgraph(nodes, edges, node_id)` |

## Tagged Tuples

### Domain Returns

Pure domain functions return plain values — no tagged tuples. They succeed or crash.

```elixir
# Level 0: returns value directly
def observe(node, confidence), do: %{node | ...}
def decay(node, factor), do: %{node | ...}
def dead?(node), do: node.relevance < @death_threshold

# NOT: {:ok, node} — there's no error case in pure math
```

### Infrastructure Returns

Infrastructure functions use tagged tuples — I/O can fail.

```elixir
# Level 2: can fail
@spec save_snapshot(map()) :: :ok | {:error, :write_failed}
@spec load_snapshot() :: {:ok, map()} | {:error, :not_found | :corrupt}
@spec ingest(Occurrence.t()) :: {:ok, map()} | {:error, :invalid_occurrence}
```

### Interface Returns

CLI and MCP functions translate between the two worlds:

```elixir
# Level 3: bridges tagged tuples to exit codes
case Store.ingest(occurrence) do
  {:ok, result} ->
    IO.puts(Jason.encode!(%{ok: true, data: result}))
    System.halt(0)
  {:error, reason} ->
    IO.puts(:stderr, "Error: #{reason}")
    System.halt(1)
end
```

## Pipeline Style

### Data-First for Piping

Every function takes the primary data as the first argument:

```elixir
# Good: pipeable
node
|> Node.observe(0.8)
|> Node.decay(0.95)
|> Node.dead?()

# Good: extraction pipeline
occurrence
|> Extraction.extract()
|> Enum.map(&apply_to_graph/1)
```

### `with` for Multi-Step Operations

When ingestion requires multiple steps that can each fail:

```elixir
def ingest(raw_json) do
  with {:ok, parsed} <- Jason.decode(raw_json),
       {:ok, occurrence} <- Occurrence.from_map(parsed),
       extractions <- Extraction.extract(occurrence),
       {:ok, result} <- Store.apply_extractions(extractions) do
    {:ok, result}
  else
    {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
    {:error, :unknown_type} -> {:error, :unsupported_occurrence}
    {:error, reason} -> {:error, reason}
  end
end
```

## Module Attributes as Constants

Domain constants live as module attributes — compiled in, no runtime lookup:

```elixir
defmodule Kerto.Graph.EWMA do
  @alpha 0.3
  @decay_factor 0.95
  @death_threshold_edge 0.05
  @death_threshold_node 0.01

  def update(current, observation) do
    @alpha * observation + (1.0 - @alpha) * current
  end

  def decay(weight, factor \\ @decay_factor) do
    weight * factor
  end
end
```

For configurable values (override via `.kerto/config.exs` or environment), use `Application.compile_env/3` with defaults:

```elixir
@decay_interval Application.compile_env(:kerto, :decay_interval_ms, :timer.hours(6))
```

## Error Handling

### Three Zones

| Zone | Strategy | Example |
|------|----------|---------|
| **Domain (L0)** | Guards + crash on invalid input | `when confidence >= 0.0` |
| **Infrastructure (L2)** | Tagged tuples for expected failures | `{:error, :write_failed}` |
| **Interface (L3)** | Catch-all, translate to exit code/JSON | `{:error, msg} -> halt(1)` |

### No `try/rescue` in Domain Code

The domain doesn't catch exceptions. If something crashes, it's a bug in the caller.

```elixir
# Bad: defensive programming in domain
def observe(node, confidence) do
  try do
    %{node | relevance: EWMA.update(node.relevance, confidence)}
  rescue
    _ -> node  # Hides bugs!
  end
end

# Good: crash loudly
def observe(node, confidence) do
  %{node | relevance: EWMA.update(node.relevance, confidence)}
end
```

### `rescue` Only at Infrastructure Boundaries

```elixir
# Infrastructure: disk I/O might fail
def save_snapshot(graph_state) do
  binary = :erlang.term_to_binary(graph_state)
  File.write!(@snapshot_path, binary)
  :ok
rescue
  e in [File.Error] -> {:error, :write_failed}
end
```

## Testing Conventions

### Level 0 Tests: Pure, Fast, Async

```elixir
defmodule Kerto.Graph.EWMATest do
  use ExUnit.Case, async: true

  describe "update/2" do
    test "new evidence moves weight toward observation" do
      assert EWMA.update(0.5, 1.0) > 0.5
    end

    test "bounds remain in [0.0, 1.0]" do
      assert EWMA.update(1.0, 1.0) <= 1.0
      assert EWMA.update(0.0, 0.0) >= 0.0
    end
  end
end
```

### Level 2 Tests: ETS Setup, Not Async

```elixir
defmodule Kerto.Infrastructure.StoreTest do
  use ExUnit.Case, async: false  # ETS tables are shared state

  setup do
    # Fresh ETS tables per test
    table = :ets.new(:test_nodes, [:set, :public])
    on_exit(fn -> :ets.delete(table) end)
    %{table: table}
  end
end
```

### Test Naming

Test names describe behavior, not implementation:

```elixir
# Good: describes domain behavior
test "observing a node increases its relevance"
test "decayed relationship below threshold is dead"
test "content-addressed ID is deterministic for same inputs"

# Bad: describes implementation
test "EWMA alpha is 0.3"
test "ETS insert works"
```

## Typespec Discipline

### All Public Functions Have Typespecs

```elixir
@spec observe(Node.t(), float()) :: Node.t()
@spec dead?(Node.t()) :: boolean()
@spec compute_id(atom(), String.t()) :: String.t()
```

### Custom Types for Domain Concepts

```elixir
@type node_id :: String.t()
@type relevance :: float()
@type confidence :: float()
@type node_kind :: :file | :module | :pattern | :decision | :error | :concept
@type relation_type :: :breaks | :caused_by | :triggers | :depends_on | :part_of |
                       :learned | :decided | :tried_failed | :often_changes_with
```

### Dialyzer

Run Dialyzer in CI. Level 0 code should have zero warnings. Infrastructure code may have deliberate suppressions for ETS operations.

```bash
mix dialyzer --format short
```

## OTP Conventions

### GenServer Client API

Every GenServer has a clean client API that hides the `GenServer.call` details:

```elixir
defmodule Kerto.Infrastructure.Store do
  use GenServer

  # Client API — this is what other modules call
  def get_node(id), do: GenServer.call(__MODULE__, {:get_node, id})
  def upsert_node(node), do: GenServer.call(__MODULE__, {:upsert_node, node})

  # Server callbacks — internal implementation
  @impl true
  def handle_call({:get_node, id}, _from, state) do
    case :ets.lookup(:kerto_nodes, id) do
      [{^id, node}] -> {:reply, {:ok, node}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end
end
```

### @impl true on Every Callback

Marks callbacks explicitly — compiler catches typos:

```elixir
@impl true
def init(opts), do: ...

@impl true
def handle_call(msg, from, state), do: ...

@impl true
def handle_info(msg, state), do: ...
```

### Process Naming

GenServers use `__MODULE__` as name — one instance per application:

```elixir
def start_link(opts) do
  GenServer.start_link(__MODULE__, opts, name: __MODULE__)
end
```

## Code Organization Within Modules

### Module Structure Order

```elixir
defmodule Kerto.Graph.Node do
  # 1. Module attributes and constants
  @enforce_keys [:id, :name, :kind]
  @death_threshold 0.01

  # 2. Struct definition
  defstruct [...]

  # 3. Type definitions
  @type t :: %__MODULE__{...}

  # 4. Public functions (most important first)
  @spec observe(t(), float()) :: t()
  def observe(...), do: ...

  @spec decay(t(), float()) :: t()
  def decay(...), do: ...

  @spec dead?(t()) :: boolean()
  def dead?(...), do: ...

  # 5. Private functions (if any)
  defp clamp(value, min, max), do: ...
end
```

### One Module Per File

No exceptions. File name matches module name in snake_case.

```
lib/kerto/graph/node.ex        → Kerto.Graph.Node
lib/kerto/graph/relationship.ex → Kerto.Graph.Relationship
lib/kerto/graph/ewma.ex         → Kerto.Graph.EWMA
```

## Dependency Rules (Enforced)

### Import/Alias Rules by Level

```elixir
# Level 0: ONLY alias within Kerto.Graph.*
alias Kerto.Graph.EWMA      # OK
alias Kerto.Graph.Identity   # OK
alias Kerto.Infrastructure.Store  # FORBIDDEN — compile should fail via boundary check

# Level 1: alias Kerto.Graph.* only
alias Kerto.Graph.Node       # OK
alias Kerto.Graph.Relationship  # OK
alias Kerto.Infrastructure.Store  # FORBIDDEN

# Level 2: alias Kerto.Graph.* and Kerto.Ingestion.* and Kerto.Rendering.*
alias Kerto.Graph.Node       # OK
alias Kerto.Ingestion.Occurrence  # OK

# Level 3: alias anything
alias Kerto.Infrastructure.Store  # OK
alias Kerto.Graph.Node       # OK
```

### Enforcement

Add a CI check that greps for illegal imports:

```bash
# Check Level 0 doesn't import anything outside Graph
grep -r "alias Kerto\." lib/kerto/graph/ | grep -v "Kerto.Graph" && exit 1 || true
```

## JSON Serialization

### Jason Protocol for Domain Structs

All domain structs derive Jason.Encoder for the cold tier:

```elixir
defmodule Kerto.Graph.Node do
  @derive {Jason.Encoder, only: [:id, :name, :kind, :relevance, :observations,
                                  :first_seen, :last_seen, :summary]}
  defstruct [...]
end
```

### Atoms to Strings in JSON

Node kinds and relation types are atoms internally, strings in JSON:

```elixir
# Internal: :file, :breaks, :caused_by
# JSON: "file", "breaks", "caused_by"

# Jason handles atom-to-string automatically
# For parsing JSON back, use explicit mapping:
def parse_kind("file"), do: :file
def parse_kind("module"), do: :module
def parse_kind(other), do: {:error, {:unknown_kind, other}}
```

## Anti-Patterns

### Things That Are Always Wrong in KERTO

| Anti-Pattern | Why | Fix |
|-------------|-----|-----|
| `IO.puts` in Level 0/1/2 | Side effect leaks into domain | Return data, let Level 3 print |
| Bare maps `%{}` for domain data | No type safety, no enforce_keys | Use structs |
| `String.to_atom/1` on user input | Atom table is bounded, DoS vector | Use explicit mapping functions |
| `:ets` operations in Level 0 | Breaks purity | Only in Level 2 |
| `Process.sleep` in tests | Flaky, slow | Use deterministic triggers |
| Mocking domain functions | Domain is pure, mock infra | Test domain directly, mock I/O |
| `@doc false` to hide functions | If it shouldn't be public, make it `defp` | Use `defp` |
| Catching all exceptions | Hides bugs | Catch specific exceptions at boundaries |
