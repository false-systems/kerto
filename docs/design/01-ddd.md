# KERTO — Domain-Driven Design

## Ubiquitous Language

These terms are the law. Code, docs, and conversation use these words with these exact meanings.

| Term | Definition | Example |
|------|-----------|---------|
| **Knowledge Node** | A thing worth knowing about. Has identity (content-addressed), kind, relevance score, and observation count. | `auth.go` (file), `OOM` (error), `JWT decision` (decision) |
| **Relationship** | A weighted, directional connection between two Knowledge Nodes. Carries confidence (EWMA), observation count, and evidence. | `auth.go --breaks(0.82)--> login_test.go` |
| **Occurrence** | An immutable event from an external source (Git, SYKLI, AI agent). Temporary input that feeds the graph. FALSE Protocol format. | `ci.run.failed` from SYKLI |
| **Knowledge Graph** | The set of all Knowledge Nodes and Relationships. The persistent memory of the project. | The graph is the product. |
| **Relevance** | A float [0.0, 1.0] representing how important a Node or Relationship is right now. Decays over time, reinforced by new evidence. | `0.82` = high relevance, `0.03` = nearly forgotten |
| **Reinforcement** | Updating a Relationship's weight with new evidence via EWMA. Multiple sources saying the same thing = higher weight. | 20 agents observe same pattern → single Relationship at 0.95 |
| **Decay** | Periodic reduction of all Relevance scores. Math-based forgetting. Nodes/Relationships below death threshold are pruned. | Every 6h: `weight *= 0.95` |
| **Death Threshold** | The Relevance below which a Relationship is pruned (0.05) or a Node is removed (0.01 with no Relationships). | `weight < 0.05 → dead` |
| **Extraction** | The process of parsing an Occurrence into Knowledge Nodes and Relationships. | CI failure → extract files, tests, `:breaks` relationships |
| **Ingestion** | Receiving an Occurrence, extracting, and upserting into the graph. The write path. | Occurrence arrives → extract → upsert graph |
| **Rendering** | Traversing the graph around a Node and producing a natural language summary. The read path for agents. | `kerto context auth.go` → human-readable summary |
| **Subgraph** | The set of Nodes and Relationships reachable from a starting Node within N hops, filtered by minimum Relevance. | Everything connected to `auth.go` within 2 hops above 0.1 weight |
| **Source** | The external system that produced an Occurrence: `:git`, `:sykli`, `:agent`. | SYKLI is a source. |
| **Evidence** | A list of texts that have reinforced a Relationship. Accumulated, never overwritten. Provides traceability and resolves concurrent agent conflicts. | Edge carries all learnings from all agents who observed it. |
| **Node Kind** | Classification of a Knowledge Node: `:file`, `:module`, `:pattern`, `:decision`, `:error`, `:concept`. | `:file` for source files, `:decision` for architectural choices |
| **Relation Type** | Classification of a Relationship: `:breaks`, `:caused_by`, `:triggers`, `:depends_on`, `:part_of`, `:learned`, `:decided`, `:tried_failed`, `:often_changes_with`. | `:breaks` for causal damage |
| **Ring Buffer** | Fixed-size FIFO store for raw Occurrences. Oldest evicted when full. | Max 1024 Occurrences |
| **Snapshot** | Periodic serialization of the graph to disk (ETF warm, JSON cold). | `Kerto.Persist` takes snapshots |
| **Hydration** | Loading a snapshot from disk into ETS on startup. | Warm ETF files → ETS tables |
| **Context** | The natural language output an agent receives when querying KERTO. | "auth.go is a high-risk file..." |

## Bounded Contexts

KERTO has **three** bounded contexts. Small tool, clear boundaries.

```
┌─────────────────────────────────────────────────────┐
│                  GRAPH (Core Domain)                │
│                                                     │
│  Knowledge Node, Relationship, Relevance,           │
│  Reinforcement, Decay, Subgraph, Death Threshold    │
│                                                     │
│  This is the product. Everything else serves it.    │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
    Occurrences flow in       Context flows out
               │                      │
┌──────────────▼──────────┐  ┌────────▼──────────────┐
│   INGESTION (Supporting)│  │  RENDERING (Supporting)│
│                         │  │                        │
│   Occurrence, Source,   │  │  Context, Subgraph,    │
│   Extraction            │  │  Summary               │
│                         │  │                        │
│   Receives raw events,  │  │  Reads graph, produces │
│   extracts Nodes +      │  │  natural language for   │
│   Relationships,        │  │  agents                │
│   upserts into Graph    │  │                        │
└─────────────────────────┘  └────────────────────────┘
```

### Context Relationships

| Upstream | Downstream | Relationship | Interface |
|----------|-----------|-------------|-----------|
| External Sources (Git, SYKLI, Agent) | Ingestion | **Conformist** — KERTO conforms to FALSE Protocol and Git's data model | Occurrence struct |
| Ingestion | Graph | **Customer/Supplier** — Ingestion calls Graph operations | `Graph.upsert_node/1`, `Graph.upsert_relationship/2` |
| Graph | Rendering | **Open Host Service** — Graph exposes query operations | `Graph.subgraph/3`, `Graph.node/1` |
| Rendering | External Agents | **Published Language** — JSON + natural language output | CLI stdout, MCP response |

### What stays OUT of each context

| Context | Does NOT contain |
|---------|-----------------|
| **Graph** | Occurrence parsing, CLI handling, disk I/O, source-specific logic |
| **Ingestion** | EWMA math, decay logic, rendering, persistence |
| **Rendering** | Write operations, extraction, decay, persistence |

Persistence (ETS/ETF/JSON) is **infrastructure** — it crosses contexts but is not a domain concern. It's implemented as a separate infrastructure module that snapshots the Graph context's state.

## Aggregates

### 1. Knowledge Node (Aggregate Root)

A Knowledge Node is the primary entity. It does NOT own Relationships — Relationships are their own aggregate (see below). This separation exists because extraction logic (e.g., `ci.run.passed` counter-evidence) needs to query and modify Relationships by target, which is a cross-aggregate operation that would violate Node's aggregate boundary.

```
Knowledge Node (root)
├── id: String (content-addressed, BLAKE2b of kind + canonical name)
├── name: String (canonical)
├── kind: NodeKind (:file | :module | :pattern | :decision | :error | :concept)
├── relevance: float [0.0, 1.0] (EWMA score)
├── observations: non_neg_integer
├── first_seen: ULID
├── last_seen: ULID
└── summary: String | nil (latest natural language description)
```

**Invariants:**
1. `id` is immutable after creation — content-addressed from `kind` + `name`
2. `kind` is immutable after creation
3. `relevance` is in `[0.0, 1.0]`
4. `name` is canonicalized on creation (paths normalized, lowercase for patterns)
5. A Node with `relevance < 0.01` AND zero connected Relationships is dead — must be pruned
6. `observations` is monotonically increasing (never decremented)

**Operations:**
- `observe(confidence)` → reinforce relevance via EWMA, increment observations, update last_seen
- `decay(factor)` → reduce relevance
- `dead?()` → relevance < 0.01 (graph-level check adds "and no connected Relationships")

### 2. Relationship (Aggregate Root)

Relationships are their own aggregate with composite identity `{source_id, relation, target_id}`. This allows extraction logic to query relationships by source, by target, or by relation type without going through a Node aggregate.

```
Relationship (root)
├── source: node_id (reference to source Knowledge Node)
├── target: node_id (reference to target Knowledge Node)
├── relation: RelationType
├── weight: float [0.0, 1.0] (EWMA confidence)
├── observations: non_neg_integer
├── first_seen: ULID
├── last_seen: ULID
└── evidence: [String] (accumulated evidence texts — new learnings append, not overwrite)
```

**Invariants:**
1. `{source, relation, target}` is unique — composite identity, no duplicates
2. `weight` is in `[0.0, 1.0]`
3. A Relationship with `weight < 0.05` is dead — must be pruned
4. `source` and `target` must reference existing Knowledge Nodes
5. `evidence` accumulates — new evidence is appended, never replaces existing entries

**Operations:**
- `reinforce(confidence, evidence_text)` → EWMA update weight, increment observations, append evidence
- `weaken(factor)` → reduce weight (used for counter-evidence, e.g., ci.run.passed)
- `decay(factor)` → reduce weight
- `dead?()` → weight < 0.05

**Why separate from Node:**
The original design had Relationship as an entity inside the Node aggregate. This broke down because:
- `ci.run.passed` extraction needs to find `:breaks` relationships *by target* to apply counter-evidence
- Rendering needs to find all relationships *pointing to* a node (incoming edges)
- The reverse index (:kerto_reverse) was a workaround for the aggregate boundary, not a natural design

With Relationship as its own aggregate, these are simple queries on the relationship's composite key.

### 3. Occurrence (Value Object with Identity)

Immutable. Created once, never modified. Lives in a Ring Buffer.

```
Occurrence
├── id: ULID (time-sortable)
├── type: String (FALSE Protocol type, e.g., "ci.run.failed")
├── source: Source (:git | :sykli | :agent)
├── summary: String (human-readable description)
├── data: map (structured payload, source-specific)
└── timestamp: DateTime
```

**Invariants:**
1. Immutable after creation — no field can change
2. `id` is a ULID (monotonic, time-sortable)
3. `type` follows FALSE Protocol naming (`domain.entity.event`)
4. `source` is one of the known sources

**Not an aggregate** — Occurrences don't own other objects. They're inputs that get consumed by Ingestion.

## Value Objects

### NodeKind
```
:file | :module | :pattern | :decision | :error | :concept
```
Immutable, equality by value. Determines how names are canonicalized.

### RelationType
```
:breaks | :caused_by | :triggers | :depends_on | :part_of |
:learned | :decided | :tried_failed | :often_changes_with
```
Immutable, equality by value. Categorizes the nature of a Relationship.

### Source
```
:git | :sykli | :agent
```
Immutable. Identifies where an Occurrence came from.

### NodeIdentity
```
{kind: NodeKind, canonical_name: String} → id: String (BLAKE2b hash)
```
Value object that computes content-addressed identity. Same inputs always produce same ID.

### EWMA
```
{alpha: float, decay_factor: float, death_threshold: float}
```
Configuration value object for the weighting algorithm. Defaults: `α=0.3`, `decay=0.95`, `death=0.05`.

## Domain Events

Events that the domain emits. These are internal signals, not FALSE Protocol Occurrences (which are external inputs).

| Event | Emitted When | Data |
|-------|-------------|------|
| `NodeCreated` | A new Knowledge Node is added to the graph | `{node_id, name, kind, source_occurrence_id}` |
| `NodeReinforced` | An existing Node receives new evidence | `{node_id, old_relevance, new_relevance}` |
| `NodeDied` | A Node's relevance decayed below threshold and was pruned | `{node_id, name, kind, lived_for}` |
| `RelationshipCreated` | A new Relationship connects two Nodes | `{source_id, target_id, relation, weight}` |
| `RelationshipReinforced` | An existing Relationship gets stronger | `{source_id, target_id, relation, old_weight, new_weight}` |
| `RelationshipDied` | A Relationship decayed below threshold and was pruned | `{source_id, target_id, relation}` |
| `OccurrenceIngested` | An Occurrence was processed and its extractions applied | `{occurrence_id, nodes_created, nodes_reinforced, relationships_created, relationships_reinforced}` |
| `DecayCycleCompleted` | A decay tick finished | `{nodes_pruned, relationships_pruned, duration_ms}` |
| `SnapshotTaken` | The graph was persisted to disk | `{format, path, size_bytes}` |

These events enable:
- Logging (what changed and why)
- Metrics (graph growth/decay rates)
- Future: streaming to AHTI

## Domain Services

### ExtractionService

Stateless service that parses an Occurrence into a list of `{:node, attrs}` and `{:relationship, attrs}` tuples.

```
extract(Occurrence) → [{:node, %{name, kind}} | {:relationship, %{source, target, relation, confidence}}]
```

One function per Occurrence type:
- `extract_ci_failure/1` — changed files × failed tasks → `:breaks` Relationships
- `extract_ci_success/1` — reinforce existing Nodes with low confidence boost
- `extract_commit/1` — co-changed files → `:often_changes_with` Relationships
- `extract_learning/1` — structured agent input → `:learned`/`:decided`/`:tried_failed`

### IdentityService

Stateless service that computes content-addressed Node IDs.

```
node_id(kind, name) → String
```

Handles name canonicalization per kind:
- `:file` → normalize path (strip `./`, make relative)
- `:pattern` → lowercase, trim
- Others → as-is

### RenderingService

Stateless service that traverses a Subgraph and produces natural language.

```
render(node, relationships) → String
```

Sections by Relationship category:
- **Caution** — `:breaks`, `:caused_by`, `:triggers`
- **Knowledge** — `:learned`, `:decided`, `:tried_failed`
- **Structure** — `:depends_on`, `:part_of`, `:often_changes_with`

Only includes Relationships above a minimum weight threshold.

## Repositories

### GraphRepository

Persistence interface for the Knowledge Graph.

```
save_snapshot(graph) → :ok | {:error, reason}
load_snapshot() → {:ok, graph} | {:error, :not_found}
```

Two implementations:
- `EtfRepository` — BEAM-native binary format (warm tier, fast)
- `JsonRepository` — JSON files in `.kerto/` (cold tier, universal)

### OccurrenceBuffer

Ring buffer for raw Occurrences.

```
push(occurrence) → :ok
list(limit) → [Occurrence]
get(id) → Occurrence | nil
```

Implementation: ETS ordered_set, ULID keys, max 1024 entries, FIFO eviction.

## Module Structure (reflecting DDD)

```
lib/kerto/
├── graph/                    # Core Domain: Knowledge Graph
│   ├── node.ex               # Knowledge Node aggregate root
│   ├── relationship.ex       # Relationship aggregate root
│   ├── node_kind.ex          # Value object
│   ├── relation_type.ex      # Value object
│   ├── ewma.ex               # Value object + pure functions
│   ├── identity.ex           # Identity service
│   └── graph.ex              # Graph operations (upsert, subgraph, decay)
│
├── ingestion/                # Supporting Context: Ingestion
│   ├── occurrence.ex         # Occurrence struct (value object with identity)
│   ├── source.ex             # Source value object
│   ├── extraction.ex         # Extraction service (occurrence → nodes + relationships)
│   └── ingest.ex             # Ingestion orchestrator (GenServer)
│
├── rendering/                # Supporting Context: Rendering
│   ├── context.ex            # Context struct (what agents receive)
│   ├── renderer.ex           # Rendering service (graph → natural language)
│   └── query.ex              # Query coordinator
│
├── infrastructure/           # Infrastructure (cross-cutting)
│   ├── store.ex              # ETS table management
│   ├── persist.ex            # Snapshot to disk (ETF + JSON)
│   ├── ring_buffer.ex        # Bounded occurrence storage
│   └── decay.ex              # Periodic decay process
│
├── interface/                # Interface layer (CLI, MCP)
│   ├── cli.ex                # CLI commands
│   └── mcp.ex                # MCP server (future)
│
├── events.ex                 # Domain event definitions
└── application.ex            # OTP application + supervision tree
```

## Dependency Direction

```
Interface → Rendering → Graph ← Ingestion
                ↑          ↑
            Infrastructure (crosses boundaries for persistence + decay)
```

- **Graph** depends on nothing (core domain, pure logic)
- **Ingestion** depends on Graph (calls upsert operations)
- **Rendering** depends on Graph (calls query operations)
- **Interface** depends on Rendering + Ingestion (routes commands)
- **Infrastructure** implements repository interfaces defined by Graph

No circular dependencies. Graph is the center. Everything points inward.

## Anti-Corruption Layer

### Git → KERTO

Git produces commits, diffs, file lists. KERTO doesn't model git internals. The `Extraction` service translates git data into KERTO domain objects:

```
Git commit → Occurrence{type: "vcs.commit"} → extract → Knowledge Nodes (files) + Relationships (:often_changes_with)
```

Git's model stays outside. Only KERTO domain objects enter the graph.

### SYKLI → KERTO

SYKLI produces FALSE Protocol Occurrences. These are already structured but contain CI-specific fields (tasks, commands, durations). The `Extraction` service maps CI concepts to graph concepts:

```
SYKLI occurrence → extract → Knowledge Nodes (files, tests) + Relationships (:breaks, :caused_by)
```

SYKLI's task model stays outside. Only Nodes and Relationships enter the graph.

### Agent → KERTO

Agents write structured learnings via CLI. The CLI validates and constructs an Occurrence, which flows through the same Ingestion path:

```
kerto learn --subject X --relation Y --target Z "description"
→ Occurrence{type: "context.learning"} → extract → Node + Relationship
```

No special path for agents. Same pipeline, same extraction, same graph operations.
