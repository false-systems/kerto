# KERTO — Local Knowledge Graph for AI Agents

> Read design docs at `docs/design/` for full context.

## Architecture

4-level dependency hierarchy. No circular dependencies, no shortcuts.

```
Level 0: lib/kerto/graph/         — ZERO deps, pure functions, 83 tests
Level 1: lib/kerto/ingestion/     — Graph only (occurrence → graph ops)
         lib/kerto/rendering/     — Graph only (graph → natural language)
Level 2: lib/kerto/infrastructure/ — Graph + L1 (ETS, persistence, timers)
Level 3: lib/kerto/interface/     — All above (CLI, MCP, application)
```

## TDD Workflow (Mandatory)

```bash
# RED: write failing test first
mix test test/graph/node_test.exs    # Should FAIL

# GREEN: minimal implementation
mix test test/graph/node_test.exs    # Should PASS

# REFACTOR: clean up
mix format && mix test
```

## CI

```bash
sykli          # runs format → compile → test (also pre-commit hook)
```

## Code Rules

- **Level 0 is pure** — no GenServer, no ETS, no IO, no Logger. Data in, data out.
- **Structs, not maps** — every domain concept is a typed struct with `@enforce_keys`
- **Guards enforce invariants** — `when is_float(weight) and weight >= 0.0`
- **`@spec` on all public functions**
- **One module per file** — file name matches module name
- **Pipeable** — primary data is always the first argument
- **Domain returns values, infra returns tagged tuples** — `node` vs `{:ok, node}`

## Key Domain Concepts

| Concept | Module | Description |
|---------|--------|-------------|
| EWMA | `Kerto.Graph.EWMA` | Weight math: update, decay, death check |
| Identity | `Kerto.Graph.Identity` | Content-addressed ID (BLAKE2b) |
| Node | `Kerto.Graph.Node` | Knowledge entity with relevance decay |
| Relationship | `Kerto.Graph.Relationship` | Weighted edge with evidence list |
| Graph | `Kerto.Graph.Graph` | Upsert, query, decay_all, prune |
| NodeKind | `Kerto.Graph.NodeKind` | :file, :module, :pattern, :decision, :error, :concept |
| RelationType | `Kerto.Graph.RelationType` | :breaks, :caused_by, :triggers, etc. |

## Anti-Patterns (Instant Rejection)

- `IO.puts` in Level 0/1/2
- Bare maps `%{}` for domain data
- `String.to_atom/1` on user input
- `:ets` in Level 0
- `try/rescue` in domain code
- Mocking domain functions (they're pure — test directly)
