# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# KERTO — Distributed Knowledge Graph for AI Agents

> Design docs at `docs/design/` (11 ADRs). Agent learning conventions at `.kerto/AGENT.md`.

Elixir `~> 1.17`. Runtime deps: `jason` (JSON for MCP), `x509` (mTLS certs). Dev: `sykli_sdk`.

## Commands

```bash
sykli                                    # CI: deps → format → compile → test (also pre-commit hook)
mix test                                 # all tests (795 tests, 0 failures)
mix test test/graph/node_test.exs        # single test file
mix test test/graph/node_test.exs:42     # single test by line number
mix format                               # format all files
mix compile --warnings-as-errors         # compile with strict warnings
mix escript.build                        # build `./kerto` CLI binary
```

## TDD Workflow (Mandatory)

```bash
# RED: write failing test first → GREEN: minimal implementation → REFACTOR
mix test test/graph/node_test.exs    # run the specific test
mix format && mix test               # then full suite
```

## Architecture

5-level dependency hierarchy. Dependencies point inward. No exceptions.

```
Level 0: lib/kerto/graph/         — ZERO deps, pure domain
Level 1: lib/kerto/ingestion/     — Graph only (occurrence → extraction ops)
         lib/kerto/rendering/     — Graph only (graph → natural language)
Level 2: lib/kerto/engine/        — L0 + L1 (ETS store, decay timer, occurrence log)
Level 3: lib/kerto/mesh/          — L0-L2 (mTLS identity, sync protocol, peer discovery)
Level 4: lib/kerto/interface/     — All above (CLI, MCP, application)
```

## Data Flow: Occurrence → Graph

This is the core pipeline — understanding it is key to working in L1/L2:

```
External event (git commit, CI failure, agent discovery)
  → Occurrence struct (type + data + source)         [L1: Ingestion.Occurrence]
  → Extraction.extract/1 dispatches by type           [L1: Ingestion.Extraction]
  → Extractor module returns [ExtractionOp]           [L1: e.g. Extractor.Commit]
  → Applier.apply_ops/3 mutates graph                 [L2: Engine.Applier]
  → Store GenServer persists                           [L2: Engine.Store]
```

Occurrence types map to extractors: `"vcs.commit"` → `Extractor.Commit`, `"ci.run.failed"` → `Extractor.CiFailure`, `"context.learning"` → `Extractor.Learning`, etc. To add a new extractor: add a clause in `Extraction.extract/1`, create the extractor module, write tests.

## Engine Supervisor Tree (L2)

`Kerto.Engine` is a Supervisor (`:one_for_one`) with 5 children in order:

```
Engine (Supervisor)
├── OccurrenceLog  — ETS ring buffer (1024 cap), ULID-keyed for time ordering
├── Store          — GenServer owning in-memory Graph, serializes mutations, ETF persistence
├── Decay          — Timer GenServer (6h interval, 0.95 factor), calls Store.decay/2
├── SessionRegistry — Tracks active agent sessions and touched files
└── PluginRunner   — Periodic scanner (5min interval), per-plugin ULID sync points
```

All children are named `:"#{engine_name}.store"`, `:"#{engine_name}.log"`, etc. Engine also manages `:pg` groups for mesh peer notifications via `join_peer_group/2` and `leave_peer_group/2`.

## Interface Layer Pattern

All transports (CLI, MCP/JSON-RPC, Unix socket) converge on the same path:

```
Transport → Parser.parse/1 → Dispatcher.dispatch/3 → Command.*.execute/2 → Response struct
```

Commands never do IO. They receive an engine atom + args map, return `Response.t()`. The transport layer handles formatting (text/JSON).

MCP tools are defined in `Interface.MCP` — each maps to a command: `kerto_context` → `Command.Context`, `kerto_learn` → `Command.Learn`, etc.

Commands include: `init`, `start`, `stop`, `status`, `context`, `learn`, `decide`, `observe`, `ingest`, `graph`, `grep`, `hint`, `bootstrap`, `scan`, `forget`, `pin`, `unpin`, `list`, `mesh`, `team`.

Commands that return structured data (`list`, `context`, `grep`) use `Serialize` for node/rel → map conversion. In text mode, `Output` formats these; in JSON mode, the maps pass through directly. The `graph` command also uses `Serialize` for its JSON dump.

## Plugin System

Plugins implement the `Kerto.Plugin` behaviour (`agent_name/0`, `scan/1`). Configured per-project via `.kerto/plugins.exs` (gitignored, local config). See `.kerto/plugins.exs.example`. The `Engine.PluginRunner` GenServer calls each plugin's `scan/1` periodically and on `kerto scan`.

## Key Invariants

- **Content-addressed identity** — `Identity.compute_id(kind, name)` is BLAKE2b of kind+name. Same file = same node ID everywhere. Enables idempotent merging and distributed consistency.
- **EWMA confidence** — weights are exponential weighted moving average (alpha 0.3). Reinforcement pulls toward observation, decay multiplies by 0.95 every 6h. Death thresholds: relationships < 0.05, nodes < 0.01 with no relationships.
- **Pinned entities** — `pinned: true` on Node/Relationship exempts from decay and pruning. Set via `kerto pin`, cleared via `kerto unpin`.
- **Initial relevance from confidence** — `Node.new/4` accepts optional confidence (default 0.5, range [0.0, 1.0]) for first insertion. `Graph.upsert_node` passes it through; subsequent observations use EWMA.
- **Relationship directionality** — `RelationType.inverse_label/1` provides inverse labels (e.g. "breaks" → "broken by"). Renderers use these when the focal node is the target, not the source.

## Key Domain Concepts

| Concept | Module | Description |
|---------|--------|-------------|
| EWMA | `Kerto.Graph.EWMA` | Weight math: update, decay, death check |
| Identity | `Kerto.Graph.Identity` | Content-addressed ID (BLAKE2b) |
| ULID | `Kerto.Graph.ULID` | Time-sortable unique IDs (pure L0, Crockford base-32) |
| Node | `Kerto.Graph.Node` | Knowledge entity with relevance decay, pinning |
| Relationship | `Kerto.Graph.Relationship` | Weighted edge with evidence list, pinning |
| Graph | `Kerto.Graph.Graph` | Upsert, query, remove, pin/unpin, subgraph BFS, search, decay_all, prune |
| NodeKind | `Kerto.Graph.NodeKind` | :file, :module, :pattern, :decision, :error, :concept |
| RelationType | `Kerto.Graph.RelationType` | :breaks, :caused_by, :triggers, :deployed_to, etc. + inverse_label/1 |
| Extraction | `Kerto.Ingestion.Extraction` | Occurrence → ExtractionOps dispatcher |
| Renderer | `Kerto.Rendering.Renderer` | Graph → natural language (Caution/Knowledge/Structure) |
| Mesh.Identity | `Kerto.Mesh.Identity` | ECDSA P-256 keypairs, PEM, fingerprinting |
| Mesh.Authority | `Kerto.Mesh.Authority` | Team CA: init, sign CSR, verify certs |
| Mesh.Sync | `Kerto.Mesh.Sync` | Occurrence-based sync protocol, ULID sync points |
| Mesh.Discovery | `Kerto.Mesh.Discovery` | mDNS + explicit peer management |
| Mesh.PeerNaming | `Kerto.Mesh.PeerNaming` | Safe peer name validation (regex + 255-byte cap, avoids raw String.to_atom) |
| Serialize | `Kerto.Interface.Serialize` | Shared node/rel → JSON-safe map conversion |
| Plugin | `Kerto.Plugin` | Behaviour for agent log readers (Claude, Logs) |

## Code Rules

- **Level 0 is pure** — no GenServer, no ETS, no IO, no Logger. Data in, data out.
- **Structs, not maps** — every domain concept is a typed struct with `@enforce_keys`
- **Guards enforce invariants** — `when is_float(weight) and weight >= 0.0`
- **`@spec` on all public functions**
- **One module per file** — file name matches module name
- **Pipeable** — primary data is always the first argument
- **Domain returns values, infra returns tagged tuples** — `node` vs `{:ok, node}`
- **Tests mirror lib/** — `lib/kerto/graph/node.ex` → `test/graph/node_test.exs`

## Anti-Patterns (Instant Rejection)

- `IO.puts` in Level 0/1
- Bare maps `%{}` for domain data
- `String.to_atom/1` on user input (use `Mesh.PeerNaming` or `Validate` module)
- `:ets` in Level 0 or Level 1
- `try/rescue` in domain code
- Mocking domain functions (they're pure — test directly)
- Circular dependencies between levels
