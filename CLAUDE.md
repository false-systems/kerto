# KERTO — Distributed Knowledge Graph for AI Agents

> Read design docs at `docs/design/` for full context.

## Architecture

5-level dependency hierarchy. Dependencies point inward. No exceptions.

```
Level 0: lib/kerto/graph/         — ZERO deps, pure domain (98 tests)
Level 1: lib/kerto/ingestion/     — Graph only (occurrence → extraction ops)
         lib/kerto/rendering/     — Graph only (graph → natural language)
Level 2: lib/kerto/engine/        — L0 + L1 (ETS store, decay timer, occurrence log)
Level 3: lib/kerto/mesh/          — L0-L2 (mTLS identity, sync protocol, peer discovery)
Level 4: lib/kerto/interface/     — All above (CLI, MCP, application)
```

243 tests, 0 failures.

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
| Graph | `Kerto.Graph.Graph` | Upsert, query, subgraph BFS, decay_all, prune |
| NodeKind | `Kerto.Graph.NodeKind` | :file, :module, :pattern, :decision, :error, :concept |
| RelationType | `Kerto.Graph.RelationType` | :breaks, :caused_by, :triggers, :deployed_to, etc. |
| Extraction | `Kerto.Ingestion.Extraction` | Occurrence → ExtractionOps dispatcher |
| Renderer | `Kerto.Rendering.Renderer` | Graph → natural language (Caution/Knowledge/Structure) |
| Mesh.Identity | `Kerto.Mesh.Identity` | ECDSA P-256 keypairs, PEM, fingerprinting |
| Mesh.Authority | `Kerto.Mesh.Authority` | Team CA: init, sign CSR, verify certs |
| Mesh.Sync | `Kerto.Mesh.Sync` | Occurrence-based sync protocol, ULID sync points |

## Anti-Patterns (Instant Rejection)

- `IO.puts` in Level 0/1
- Bare maps `%{}` for domain data
- `String.to_atom/1` on user input
- `:ets` in Level 0 or Level 1
- `try/rescue` in domain code
- Mocking domain functions (they're pure — test directly)
- Circular dependencies between levels
