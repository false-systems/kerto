# KERTO — Human Curation Design

## ADR-011: Manual Knowledge Curation — Forget, Pin, Unpin

**Status:** Proposed
**Context:** EWMA handles staleness — unused knowledge decays and gets pruned. But EWMA cannot handle *incorrectness*. Wrong knowledge decays slowly instead of disappearing. And important-but-infrequent knowledge (architectural decisions, hard-won lessons) decays when it shouldn't. Humans need manual controls to curate the graph.

## The Problem

### Wrong knowledge persists

An agent records "auth.go causes OOM." It's wrong — the OOM was from a different service. The relationship sits in the graph at low weight, occasionally surfacing as a caution. EWMA will decay it, but never fully remove it unless it drops below the 0.05 threshold. That could take weeks, and in the meantime agents get misleading context.

### Important knowledge decays

A team decides "Postgres over Mongo for ACID guarantees." Nobody mentions this for three weeks because it's settled. EWMA decays it to irrelevance. A new agent starts evaluating database options without knowing about the prior decision.

### No way to inspect and clean up

The graph accumulates noise over time — stale file references, one-off errors that aren't patterns, relationships from exploratory sessions that went nowhere. There's no way for a human to browse and prune.

## The Solution: Three Commands

### `kerto forget` — Delete knowledge

```bash
# Remove a node and all its relationships
kerto forget auth.go

# Remove a specific relationship
kerto forget auth.go --breaks test_suite

# Remove by node kind
kerto forget --kind error auth_oom
```

Forget is immediate and permanent. The node/relationship is deleted from the graph. If the same knowledge re-enters through a future occurrence, it starts fresh.

**Implementation:** New command at L4. Calls `Graph.remove_node/2` or `Graph.remove_relationship/4` (new functions at L0).

### `kerto pin` — Exempt from decay

```bash
# Pin a node — its relevance won't decay
kerto pin auth.go

# Pin a specific relationship
kerto pin auth.go --decided jwt_auth
```

Pinned nodes and relationships skip the decay pass. Their weights stay where they are. New observations still reinforce them normally.

**Implementation:** Add `pinned :: boolean()` field to `Node` and `Relationship` structs (default `false`). `Graph.decay_all/2` skips pinned entities. New command at L4.

### `kerto unpin` — Resume decay

```bash
kerto unpin auth.go
```

Removes the pin. The entity resumes normal decay from its current weight.

### `kerto list` — Browse the graph for curation

```bash
# List all nodes, sorted by relevance
kerto list

# List relationships for a specific node
kerto list auth.go

# List pinned entities
kerto list --pinned

# List low-weight entities (candidates for pruning)
kerto list --below 0.1
```

Humans can't curate what they can't see. List provides the inspection layer that makes forget/pin useful.

## Domain Changes (Level 0)

### Node struct

```elixir
defstruct [
  :id, :kind, :name, :relevance, :observations,
  :first_seen, :last_seen,
  pinned: false  # NEW
]
```

### Relationship struct

```elixir
defstruct [
  :source_id, :relation, :target_id, :weight, :observations,
  :evidence, :first_seen, :last_seen,
  pinned: false  # NEW
]
```

### Graph functions

```elixir
# New functions
Graph.remove_node(graph, node_id) :: Graph.t()
Graph.remove_relationship(graph, source_id, relation, target_id) :: Graph.t()
Graph.pin_node(graph, node_id) :: Graph.t()
Graph.unpin_node(graph, node_id) :: Graph.t()
Graph.pin_relationship(graph, source_id, relation, target_id) :: Graph.t()
Graph.unpin_relationship(graph, source_id, relation, target_id) :: Graph.t()
Graph.list_nodes(graph, opts) :: [Node.t()]  # already exists, extend with filters
```

### Decay change

```elixir
# Graph.decay_all/2 skips pinned entities
def decay_all(graph, factor) do
  graph
  |> decay_nodes(factor)    # skip where node.pinned == true
  |> decay_relationships(factor)  # skip where rel.pinned == true
  |> prune()
end
```

Pinned entities are also exempt from pruning regardless of weight.

## Interface Changes (Level 4)

Four new commands:

| Command | Args | Engine Call |
|---------|------|------------|
| `forget` | `name`, `--relation`, `--kind` | `Graph.remove_node/2` or `Graph.remove_relationship/4` |
| `pin` | `name`, `--relation` | `Graph.pin_node/2` or `Graph.pin_relationship/4` |
| `unpin` | `name`, `--relation` | `Graph.unpin_node/2` or `Graph.unpin_relationship/4` |
| `list` | `name`, `--pinned`, `--below`, `--kind` | `Graph.list_nodes/2` with filters |

All commands follow the existing pattern: `execute(engine, args) :: Response.t()`.

## Mesh Considerations

- `forget` produces a `graph.forget` occurrence that syncs via mesh — all peers delete the same entity
- `pin`/`unpin` produce `graph.pin`/`graph.unpin` occurrences — peers respect the pin
- These are "administrative" occurrence types, not knowledge types

## Design Decisions

### Why not soft-delete?

Simplicity. A forgotten node is gone. If the same knowledge re-enters via a future CI failure or agent observation, it creates a fresh node. Soft-delete adds state tracking complexity for no practical benefit — if you told the system to forget something, you meant it.

### Why pin instead of "set weight to 1.0"?

Setting weight to 1.0 would be overwritten on the next decay pass. Pinning is a durable flag that survives decay cycles. It also communicates intent — "this is important" vs "this just happened to score high."

### Why a boolean pin instead of a decay override factor?

A configurable decay factor per entity is over-engineering. The real-world need is binary: either knowledge should decay normally, or it's important enough that a human said "keep this." YAGNI.

### Why list as a separate command?

`kerto graph` already dumps the full graph as JSON/DOT, but that's for programmatic use. `kerto list` is human-readable, filterable, and designed for curation workflows: scan → inspect → forget/pin.

## Implementation Order

1. Add `pinned` field to `Node` and `Relationship` structs (L0)
2. Add `remove_node/2`, `remove_relationship/4` to `Graph` (L0)
3. Add `pin_node/2`, `unpin_node/2`, `pin_relationship/4`, `unpin_relationship/4` to `Graph` (L0)
4. Update `Graph.decay_all/2` to skip pinned entities (L0)
5. Extend `Graph.list_nodes/2` with filter options (L0)
6. Add `forget`, `pin`, `unpin`, `list` commands (L4)
7. Register commands in dispatcher and parser (L4)
8. Add mesh occurrence types for forget/pin/unpin (L3)
