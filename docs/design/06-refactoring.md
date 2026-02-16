# KERTO — Refactoring Strategy

## Overview

KERTO is a new project, but it's designed to evolve: from standalone CLI to SYKLI plugin, from Elixir to Vaisto, from local to AHTI-connected. This document defines the refactoring patterns and evolution strategy that keep the codebase healthy as it grows.

## Evolution Phases

### Phase 1: Standalone CLI (v0.1)

```
kerto init → kerto learn → kerto context → kerto graph
```

Single binary (escript). Graph in ETS, snapshots to `.kerto/`. Three input sources: Git hooks, manual `kerto learn`, manual `kerto ingest`.

**Exit criteria for Phase 1:**
- All Level 0 tests pass (pure domain)
- CLI commands work end-to-end
- Snapshot/hydration cycle is stable
- Decay cycle prunes correctly

### Phase 2: SYKLI Plugin (v0.2)

KERTO runs as an OTP application inside SYKLI's BEAM VM. SYKLI writes directly via Elixir function calls.

**Refactoring required:**
- Extract `Kerto.Application` to be startable as a child supervisor
- Ensure Store can receive events from SYKLI without CLI overhead
- No changes to Level 0/1 — only Level 2 (Store) gets a new write path

**Pattern: Parallel Change (Expand/Contract)**
1. **Expand**: Add `Store.ingest/1` as a direct Elixir API alongside CLI
2. **Migrate**: SYKLI calls `Store.ingest/1` instead of shelling out to CLI
3. **Contract**: CLI still works for standalone users

### Phase 3: MCP Server (v0.3)

Add MCP interface for native AI agent integration. Agents discover KERTO tools via MCP protocol.

**Refactoring required:**
- Add `Kerto.Interface.MCP` module (Level 3)
- Reuse same rendering/ingestion paths as CLI
- No changes to Level 0/1/2

**Pattern: Branch by Abstraction**
- CLI and MCP both call the same underlying functions
- Interface layer is thin — just protocol translation

### Phase 4: AHTI Connection (v0.4+)

KERTO sends pattern occurrences to AHTI via FALSE Protocol over NATS.

**Refactoring required:**
- Add `Kerto.Infrastructure.NATSPublisher` (Level 2)
- Pattern detector produces `context.pattern` occurrences
- Publisher sends them upstream

## Safe Refactoring Rules

### Rule 1: Never Refactor Without Tests

Before touching any code:

```bash
# Run existing tests
mix test

# If adding new code path, write test first (TDD)
# If changing existing code, verify characterization tests exist
```

Level 0 tests are the safety net. They're fast, pure, and exhaustive. If a refactoring breaks a Level 0 test, the refactoring is wrong.

### Rule 2: One Structural Change Per Commit

```
# Good commit sequence:
1. "extract EWMA.clamp/3 from Node.observe/2"
2. "rename Node.weight to Node.relevance"
3. "move canonicalization from Identity to NodeKind"

# Bad: single commit doing all three
```

### Rule 3: Behavior Changes and Structural Changes Are Separate

Never mix feature work with refactoring in the same commit.

```
# Good:
commit 1: "refactor(graph): extract subgraph traversal from Graph module"
commit 2: "feat(graph): add depth-limited traversal option"

# Bad:
commit 1: "refactor graph module and add depth limit"
```

## Anticipated Refactorings

### 1. Extract Value Objects (Phase 1)

As the domain stabilizes, some fields will reveal themselves as value objects:

**Candidate: Confidence**
```elixir
# Before: raw float everywhere
@spec observe(Node.t(), float()) :: Node.t()

# After: Confidence value object with validation
defmodule Kerto.Graph.Confidence do
  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: float()}

  def new(value) when is_float(value) and value >= 0.0 and value <= 1.0 do
    %__MODULE__{value: value}
  end
end
```

**When to do it:** Only when the same validation/constraint appears in 3+ places. Don't extract prematurely.

**Candidate: NodeName**
```elixir
# Before: raw string + scattered canonicalization
Identity.compute_id(:file, "./src/auth.go")

# After: NodeName handles canonicalization internally
defmodule Kerto.Graph.NodeName do
  def new(:file, path), do: %__MODULE__{value: normalize_path(path)}
  def new(:pattern, name), do: %__MODULE__{value: String.downcase(String.trim(name))}
  def new(_kind, name), do: %__MODULE__{value: name}
end
```

**When to do it:** When canonicalization bugs appear because the logic is duplicated.

### 2. Extract Pattern Detector (Phase 2)

Initially, pattern detection is simple (threshold check after decay). As it grows:

```
# Before: inline in Decay GenServer
def handle_info(:tick, state) do
  # decay all
  # check for patterns   ← this grows
  # emit occurrences
end

# After: extracted module
defmodule Kerto.Graph.PatternDetector do
  @spec detect(map(), map()) :: [Occurrence.t()]
  def detect(nodes, edges) do
    edges
    |> Enum.filter(&high_confidence_pattern?/1)
    |> Enum.map(&build_pattern_occurrence/1)
  end
end
```

**When to do it:** When the tick handler exceeds 30 lines or pattern logic needs its own tests.

### 3. Introduce Behaviours for Extractors (Phase 1)

The extraction module dispatches by occurrence type. As new types are added:

```elixir
# Before: case statement in Extraction
def extract(%Occurrence{type: "ci.run.failed"} = occ), do: CiFailure.extract(occ)
def extract(%Occurrence{type: "ci.run.passed"} = occ), do: CiSuccess.extract(occ)
def extract(%Occurrence{type: "vcs.commit"} = occ), do: Commit.extract(occ)

# If this grows beyond 6-7 types, refactor to:
defmodule Kerto.Ingestion.Extractor do
  @callback extract(Occurrence.t()) :: [{:node, map()} | {:relationship, map()}]
end

@extractors %{
  "ci.run.failed" => Kerto.Ingestion.Extractor.CiFailure,
  "ci.run.passed" => Kerto.Ingestion.Extractor.CiSuccess,
  "vcs.commit" => Kerto.Ingestion.Extractor.Commit,
  # ...
}

def extract(%Occurrence{type: type} = occ) do
  case Map.get(@extractors, type) do
    nil -> {:error, {:unknown_type, type}}
    module -> module.extract(occ)
  end
end
```

**When to do it:** When the 6th extractor type is added. Not before.

### 4. Split Store into Read/Write (Phase 2+)

When SYKLI and MCP are both writing, the Store GenServer may become a bottleneck:

```
# Before: single Store GenServer handles reads and writes
Store.get_node(id)      # read
Store.upsert_node(node) # write

# After: ETS reads are direct (no GenServer), writes serialized
# Reads: direct ETS lookup (concurrent, no bottleneck)
# Writes: GenServer serializes mutations
```

**When to do it:** When profiling shows Store.get_node latency under concurrent load. Not before.

### 5. Persistence Abstraction (Phase 3+)

Currently persistence is hardcoded to ETF + JSON. If new formats are needed:

```elixir
# Before: direct File.write! in Persist
def save do
  File.write!(".kerto/graph.etf", :erlang.term_to_binary(state))
  File.write!(".kerto/graph.json", Jason.encode!(state))
end

# After: behaviour-based
defmodule Kerto.Infrastructure.PersistBackend do
  @callback save(map()) :: :ok | {:error, term()}
  @callback load() :: {:ok, map()} | {:error, term()}
end
```

**When to do it:** When a third persistence format is actually needed. Two formats (ETF + JSON) don't justify the abstraction.

## Code Smells to Watch For

### KERTO-Specific Smells

| Smell | Signal | Likely Fix |
|-------|--------|------------|
| **Leaky Purity** | Level 0 function calls Logger, ETS, or GenServer | Move I/O to Level 2, pass data through |
| **God Store** | Store GenServer handles ingestion, query, persistence, decay | Extract into specialized GenServers |
| **Shotgun Extraction** | Adding a new occurrence type requires changes in 4+ files | Introduce Extractor behaviour |
| **Fat Occurrence** | Occurrence struct grows fields for every source type | Keep `data` as source-specific map, parse in extractors |
| **Stale Test Fixtures** | Test fixtures hardcode ULIDs or timestamps that break | Use factory functions that generate fresh data |
| **Boundary Violation** | Level 1 module aliases Level 2 module | Move the needed logic to the correct level |

### Priorities

1. **Boundary violations** — fix immediately, they spread
2. **Leaky purity** — fix before it becomes the norm
3. **God Store** — watch for it, split when it appears
4. **Everything else** — address when it causes pain

## Refactoring Workflow

### For Domain Refactorings (Level 0)

```
1. Identify the smell
2. Write test that captures current behavior (if missing)
3. Run full Level 0 test suite (should take <1 second)
4. Make ONE structural change
5. Run tests — must still pass
6. Commit with descriptive message
7. Repeat steps 4-6 until done
```

### For Infrastructure Refactorings (Level 2)

```
1. Identify the smell
2. Ensure integration tests exist for the affected path
3. Run full test suite
4. Make ONE structural change
5. Run tests — must still pass
6. Test manually with CLI if the change affects I/O
7. Commit
8. Repeat
```

### For Cross-Level Refactorings

```
1. Design the target state
2. Expand: add new path alongside old
3. Migrate: move callers to new path one at a time, testing after each
4. Contract: remove old path
5. Each step is a separate commit
```

## Technical Debt Budget

KERTO is a small tool. The debt budget is small.

### Acceptable Debt (v0.1)

- Hardcoded defaults instead of config file parsing
- No MCP (CLI only)
- No NATS publisher (standalone only)
- Simple pattern detection (threshold check only)
- No warm cache for rendered context (render on every query)

### Unacceptable Debt (Never)

- Boundary violations between levels
- Side effects in Level 0
- Missing tests for domain logic
- Bare maps instead of structs for domain entities
- Swallowed errors in infrastructure
- `String.to_atom/1` on external input

## Metrics to Track

### Code Health Indicators

| Metric | Threshold | How to Check |
|--------|-----------|-------------|
| Level 0 test count | >= 2x number of public functions | `mix test test/graph/ --trace \| wc -l` |
| Level 0 test time | < 1 second total | `mix test test/graph/ --trace` |
| Boundary violations | 0 | CI grep check |
| Dead code | 0 unreachable functions | `mix xref unreachable` |
| Dialyzer warnings | 0 for Level 0, minimal elsewhere | `mix dialyzer` |
| Module size | < 200 lines per module | `wc -l lib/kerto/**/*.ex` |
| Function size | < 30 lines per function | Code review |
