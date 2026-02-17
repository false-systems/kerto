# KERTO

> *kerto* (Finnish): refrain, to tell

**Your project has a story. KERTO remembers it.**

Like CLAUDE.md but it writes itself, gets smarter every day, and shares knowledge across your team.

## The Problem

AI assistants lose context between sessions. Every conversation starts from zero. The AI doesn't know what broke last week, what was decided last month, or what patterns keep recurring.

The #1 bottleneck in AI-assisted development isn't models or prompts — it's **context**.

## What KERTO Does

KERTO is a local knowledge graph that accumulates project knowledge over time. It watches git, CI results, and AI agent discoveries — then gives the next AI session everything it needs.

```
AI reads context ←── KERTO ──→ AI writes discoveries
                       ↑
                   git · CI · agents
```

The loop nobody else has: **AI teaches the next AI.**

```bash
# an agent learns something
kerto learn --subject auth.go --relation caused_by --target "unbounded cache" \
  "auth.go OOM was caused by unbounded cache in the session store"

# next agent gets that context automatically
kerto context auth.go
# → "auth.go is a high-risk file (0.92 relevance, seen 12x).
#    Known issue: OOM caused by unbounded cache in session store.
#    Breaks: login_test.go (0.85), session_test.go (0.71)"
```

## How It Works

- **Knowledge graph** with EWMA-weighted edges that decay over time
- **Content-addressed identity** — same file from 20 agents = one node
- **Evidence accumulates** — multiple sources saying the same thing = higher confidence
- **Math-based forgetting** — old knowledge fades, recent knowledge stays sharp
- **Distributed mesh** — BEAM nodes share knowledge via mTLS, no central server

```
High confidence (0.8+):
  auth.go ──breaks──→ login_test.go  (0.92, seen 12x)
  deploy   ──triggers──→ restart     (0.85, seen 8x)

Fading (0.3-0.5):
  cache.go ──caused_by──→ OOM        (0.34, last seen 3w ago)

Dying (< 0.1):
  old_api  ──depends_on──→ legacy_db  (0.07, last seen 2mo ago)
```

## Team Mesh

KERTO nodes connect directly over BEAM distribution with mutual TLS. No central server. Knowledge flows as occurrences — each node ingests independently, graphs converge automatically.

```
Kerto@dev-a ←──mTLS/BEAM──→ Kerto@dev-b
     ↑                            ↑
  local CI / git / agents      local CI / git / agents
```

Dev A discovers "auth.go breaks login_test" → syncs to Dev B in seconds → Dev B's AI agent knows before touching auth.go. No Slack message needed.

## Install

```bash
brew install kerto
```

## Usage

```bash
kerto init              # scan git history, build initial graph
kerto context <file>    # what do I know about this file?
kerto learn ...         # agent writes back a discovery
kerto status            # show graph health

# team mesh
kerto team init         # create team CA
kerto mesh start        # connect to peers via mDNS + mTLS
kerto mesh status       # show connected peers, sync state
```

KERTO also runs as an **MCP server** — Claude Code, Cursor, and any MCP-compatible tool discover it automatically. Zero integration work.

## Architecture

Built in Elixir on the BEAM. Pure functional domain layer, OTP for concurrency, ETS for speed, BEAM distribution for mesh.

```
Level 0: Graph           — Pure domain (EWMA, identity, graph ops)
Level 1: Ingestion       — Occurrences → graph ops
         Rendering       — Graph → natural language for agents
Level 2: Engine          — ETS store, decay timer, occurrence log
Level 3: Mesh            — mTLS identity, sync protocol, peer discovery
Level 4: Interface       — CLI, MCP server, application
```

243 tests. Zero `map[string]interface{}` equivalent. Dependencies point inward — no exceptions.

## License

MIT
