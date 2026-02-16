# KERTO

> *kerto* (Finnish): refrain, to tell

**Your project has a story. KERTO remembers it.**

Like CLAUDE.md but it writes itself and gets smarter every day.

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

```
High confidence (0.8+):
  auth.go ──breaks──→ login_test.go  (0.92, seen 12x)
  deploy   ──triggers──→ restart     (0.85, seen 8x)

Fading (0.3-0.5):
  cache.go ──caused_by──→ OOM        (0.34, last seen 3w ago)

Dying (< 0.1):
  old_api  ──depends_on──→ legacy_db  (0.07, last seen 2mo ago)
```

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
```

KERTO also runs as an **MCP server** — Claude Code, Cursor, and any MCP-compatible tool discover it automatically. Zero integration work.

## Architecture

Built in Elixir on the BEAM. Pure functional domain layer, OTP for concurrency, ETS for speed.

- **Level 0:** Pure domain — graph, EWMA, identity (zero deps, 83 tests)
- **Level 1:** Ingestion + Rendering (occurrence parsing, context generation)
- **Level 2:** Infrastructure (ETS, persistence, decay timer)
- **Level 3:** Interface (CLI, MCP server, Unix socket daemon)

## License

MIT
