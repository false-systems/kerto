# KERTO

> *kerto* (Finnish): refrain, to tell

**Persistent memory for AI coding agents.**

KERTO is a knowledge graph that lives in your project. It learns from git history, CI failures, and agent sessions — then gives the next AI session everything it needs. Knowledge accumulates, old facts fade, and your whole team shares what their agents discovered.

```
Session 1 (Claude):  "auth.go OOMed because of an unbounded session cache"
                          ↓  kerto learn
                     ┌─────────┐
                     │  KERTO  │  ← also watching: git commits, CI results
                     └─────────┘
                          ↓  kerto context auth.go
Session 2 (Cursor):  "auth.go (file) — relevance 0.92, observed 12 times
                      Caution: breaks login_test.go (weight 0.85)
                      Knowledge: caused_by unbounded cache (weight 0.80)"
```

The loop nobody else has: **AI teaches the next AI.**

## Why

AI assistants lose context between sessions. Every conversation starts from zero — the AI doesn't know what broke last week, what was decided last month, or what patterns keep recurring.

CLAUDE.md helps, but someone has to write it and keep it current. KERTO writes itself.

- **Knowledge graph** with EWMA-weighted edges that decay over time
- **Content-addressed identity** — same file from 20 agents = one node (BLAKE2b)
- **Evidence accumulates** — multiple sources saying the same thing = higher confidence
- **Math-based forgetting** — stale knowledge fades, recent knowledge stays sharp
- **Distributed mesh** — BEAM nodes share knowledge via mTLS, no central server

```
High confidence (0.8+):
  auth.go ──breaks──→ login_test.go  (0.92, seen 12x)
  deploy   ──triggers──→ restart     (0.85, seen 8x)

Fading (0.3-0.5):
  cache.go ──caused_by──→ OOM        (0.34, last seen 3w ago)

Dying (< 0.1):
  old_api  ──depends_on──→ legacy_db  (0.07, auto-pruned soon)
```

## Quick Start

```bash
# build from source (Elixir ~> 1.17)
mix deps.get && mix escript.build

# initialize in your project
./kerto init          # creates .kerto/, .mcp.json, .gitignore entries
./kerto bootstrap     # seed the graph from git history
./kerto status        # Nodes: 42  Relationships: 18  Occurrences: 0
```

### MCP Integration (Claude Code, Cursor, etc.)

`kerto init` creates a `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "kerto": {
      "command": "kerto",
      "args": ["mcp"]
    }
  }
}
```

MCP-compatible tools discover KERTO's 16 tools automatically — `kerto_context`, `kerto_learn`, `kerto_grep`, `kerto_hint`, and more. No configuration needed.

### CLI

```bash
# query
kerto context auth.go                    # rendered context for a file
kerto context auth.go --json             # structured JSON for machines
kerto grep "OOM" --evidence              # search relationship evidence
kerto grep auth --kind file              # search nodes by name
kerto list --type rels --relation breaks # list relationships with filters
kerto hint --files auth.go,handler.go    # compact hints before editing

# record knowledge
kerto learn "auth.go OOMs under load" --subject auth.go
kerto learn "auth depends on session" --subject auth.go \
  --target session.go --relation depends_on
kerto decide "use JWT for auth" --subject auth-strategy

# observe sessions
kerto observe --summary "Fixed OOM in auth by adding LRU cache" \
  --files "auth.go,cache.go"

# manage the graph
kerto pin --node auth.go                 # never decay this node
kerto forget --node old_api.go           # remove from graph
kerto graph --format dot | dot -Tpng -o graph.png

# all commands support --json for structured output
kerto list --json
kerto context auth.go --json
kerto grep auth --json
```

### Passive Learning (Plugins)

KERTO can scan AI agent conversation logs and learn from them automatically:

```elixir
# .kerto/plugins.exs
[Kerto.Plugin.Claude]
```

The Claude plugin reads `~/.claude/projects/` JSONL files and extracts file reads, tool errors, and patterns — no agent configuration required. Run `kerto scan` to trigger manually or let the engine scan every 5 minutes.

## Team Mesh

KERTO nodes connect directly over BEAM distribution with mutual TLS. No central server. Knowledge flows as occurrences — each node ingests independently, graphs converge via content-addressed identity.

```
Kerto@dev-a ←──mTLS/BEAM──→ Kerto@dev-b
     ↑                            ↑
  local CI / git / agents      local CI / git / agents
```

```bash
kerto team --action init --name my-team   # create team CA
kerto team --action join --name dev-a     # generate keypair + CSR
kerto mesh --action connect --peer kerto@dev-b.local
```

Dev A discovers "auth.go breaks login_test" → syncs to Dev B in seconds → Dev B's AI agent knows before touching auth.go.

## Architecture

Built in Elixir on the BEAM. Pure functional domain layer, OTP supervision for resilience, ETS for concurrent reads, BEAM distribution for mesh.

```
Level 0: lib/kerto/graph/         Pure domain — EWMA, identity, graph ops, search
Level 1: lib/kerto/ingestion/     Occurrences → extraction ops
         lib/kerto/rendering/     Graph → natural language for agents
Level 2: lib/kerto/engine/        ETS store, decay timer, occurrence log, plugins
Level 3: lib/kerto/mesh/          mTLS identity, sync protocol, peer discovery
Level 4: lib/kerto/interface/     CLI, MCP server, daemon, serialization
```

Dependencies point inward — no exceptions. Level 0 has zero dependencies, no GenServer, no ETS, no IO. Pure data in, data out.

### Engine Supervisor Tree

```
Engine (Supervisor, one_for_one)
├── OccurrenceLog    ETS ring buffer (1024 cap), ULID-keyed
├── Store            GenServer, in-memory Graph, ETF persistence
├── Decay            Timer (6h interval, 0.95 factor)
├── SessionRegistry  Active agent sessions and touched files
└── PluginRunner     Periodic scanner (5min), per-plugin sync points
```

### Interface Pipeline

All transports (CLI, MCP/JSON-RPC, Unix socket daemon) converge:

```
Transport → Parser.parse/1 → Dispatcher.dispatch/3 → Command.*.execute/2 → Response
```

Commands never do IO. They receive an engine name + args map, return `Response.t()`. Transports handle formatting — `Output` for CLI text, `Serialize` for JSON, `Protocol` for daemon wire format.

### Key Invariants

| Invariant | Mechanism |
|-----------|-----------|
| Identity convergence | BLAKE2b(kind + name) — same file = same node everywhere |
| Confidence weighting | EWMA (α=0.3): reinforcement pulls toward observation |
| Knowledge decay | Multiply by 0.95 every 6h; death at < 0.05 (rels) / < 0.01 (nodes) |
| Pinned entities | `pinned: true` exempts from decay and pruning |
| Distributed merge | Content-addressed IDs enable conflict-free union merge |

## Status

Active development. 795 tests, 0 failures. Two runtime dependencies: `jason`, `x509`.

Core (working): knowledge graph, EWMA decay, CLI, MCP server, structured JSON output, graph search, plugins, daemon mode, persistence.

Mesh (working): mTLS identity, team CA, peer naming, sync protocol, mDNS discovery.

## License

MIT
