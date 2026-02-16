# KERTO - Your Project's Story

> *kerto* (Finnish): refrain, to tell

## One-Liner

KERTO is a local context database that gives your project memory across AI sessions.

## The Principle

> "What is hateful to you, do not do to your fellow." — Hillel

You wouldn't want someone reviewing every line you write with zero context about why you wrote it. You'd want them to give you the background, the history, the "here's what we tried before." Then trust you to do good work.

The industry is building guardrails — review tools, audit trails, checkpoints — all assuming AI is the problem and humans need to police it. We believe the opposite: **AI isn't dangerous, it's blind.** Give it context, and it does the right thing.

Instead of being AI's cop, give AI better tools.

## The Problem

AI assistants lose context between sessions. Every conversation starts from zero. The AI doesn't know what broke last week, what was decided last month, or what patterns keep recurring. Developers waste time re-explaining, and AI keeps making the same mistakes.

The #1 bottleneck in AI-assisted development isn't models or prompts — it's **context**.

## What KERTO Does

KERTO watches the tools in your development workflow and accumulates structured knowledge over time.

Three inputs:

| Source | What KERTO Captures |
|--------|--------------------|
| **Git** | Commits, branches, diffs — what changed and when |
| **SYKLI** | CI results, failures, occurrences — what broke and why |
| **AI agents** | Decisions, learnings, error resolutions — what was tried |

One store. Every next AI session starts with all of it.

## What KERTO Is Not

- Not a system monitor — doesn't watch your file system, processes, or network
- Not a dashboard — no UI, built for machines
- Not a CI tool — SYKLI does CI, KERTO stores what SYKLI learned
- Not an observability platform — TAPIO/AHTI do that, KERTO stores what they know

## Architecture: Knowledge Graph with EWMA Decay

KERTO's internal engine is a **knowledge graph** — entities connected by weighted relationships that decay over time.

### The Core Data Model

Three types:

```
Entity   — anything worth knowing about (a file, a module, a pattern, a decision)
Edge     — a relationship between two entities, with confidence weight
Occurrence — raw input that feeds the graph (temporary, ring buffer)
```

### How Knowledge Flows

```
Occurrence arrives (from Git, SYKLI, or AI agent)
    ↓
Extract entities and relationships
    ↓
Upsert into graph: create entity or reinforce existing
    ↓
EWMA updates edge weights (new evidence strengthens, time weakens)
    ↓
Agent queries graph → gets natural language summary
```

### EWMA (Exponential Weighted Moving Average)

Every edge has a weight that represents confidence. New evidence reinforces it. Time decays it. No eviction logic needed — math does the forgetting.

```
New evidence:    weight = α × observation + (1 - α) × old_weight
Decay (every 6h): weight = weight × 0.95
Death:            weight < 0.05 → edge removed

α = 0.3 (responsive to new evidence, remembers history)
```

20 agents learning the same thing = 1 edge with high confidence.
Nobody mentions something for months = weight decays to zero = forgotten.

### Entity Kinds

```
:file       — source files (auth.go, parser.go)
:module     — logical modules (auth, payment)
:pattern    — recurring patterns ("auth changes break login tests")
:decision   — architectural decisions ("JWT over sessions")
:error      — known error types (OOM, connection refused)
:concept    — abstract concepts (caching, concurrency)
```

### Edge Relations

```
:breaks             — "auth.go breaks login_test.go"
:caused_by          — "OOM caused by unbounded cache"
:triggers           — "deploy triggers restart"
:depends_on         — "auth.go depends on jwt_config.go"
:part_of            — "auth.go part of auth module"
:learned            — "agent learned: cache must be bounded"
:decided            — "team decided JWT over sessions"
:tried_failed       — "approach X was tried and failed because Y"
:often_changes_with — "auth.go often changes with auth_test.go"
```

### Memory Budget

The graph self-regulates:

```
Max entities:    1000 (each ~200 bytes active)
Max raw occurrences: 1024 (ring buffer, FIFO eviction)
Disk budget:     10MB hard cap
```

Entities and edges that aren't reinforced decay and die. The graph gets **denser**, not bigger.

### Deduplication

Entity identity is content-addressed: `id = blake2b(kind + canonical_name)`. The same file mentioned by 20 agents in 20 sessions = one entity. Always.

Edges keyed by `{source_id, relation, target_id}`. Same relationship from multiple sources reinforces the weight, doesn't create duplicates.

## How It Works

```
kerto init
# done. your project now has a story.
```

KERTO runs as a BEAM/OTP application. Three-tier storage (proven in SYKLI):

- **Hot**: ETS (in-memory, concurrent reads, O(log n) lookups)
- **Warm**: ETF files (BEAM-native binary, hydrated on startup)
- **Cold**: JSON on disk (any tool can read, zero integration)

### OTP Supervision Tree

```
Kerto.Application
├── Kerto.Store         — ETS table management (entities, edges, occurrences, names)
├── Kerto.Ingest        — GenServer: receives occurrences, extracts entities + edges
├── Kerto.Decay         — Periodic process: EWMA decay every 6h, prunes dead edges
├── Kerto.Persist       — Periodic process: snapshots ETS to ETF/JSON on disk
└── Kerto.Query         — Reads graph, renders natural language summaries
```

### Interfaces

| Consumer | Interface | Details |
|----------|-----------|---------|
| **AI agents** | CLI | `kerto query`, `kerto learn` — structured JSON out |
| **AI agents (native)** | MCP server | Tool discovery, richer interaction |
| **SYKLI** | BEAM messages | Same VM, direct ETS or GenServer calls |
| **Git** | Hooks | post-commit, post-checkout — passive, no config |
| **Disk** | `.kerto/` directory | JSON cold storage, any tool can read |
| **TAPIO/AHTI (future)** | FALSE Protocol | gRPC or NATS, same as existing ecosystem |

## The AI Interface

Agents don't see the graph. They see **natural language summaries** rendered from it.

```bash
# Agent asks about a file
kerto context auth.go

# KERTO traverses the graph, scores by relevance, renders:
# "auth.go is a high-risk file. Changes break login_test.go
#  (82% confidence, seen 12 times). Depends on jwt_config.go.
#  Team decision: JWT over sessions (stateless requirement).
#  Last CI failure: 3 days ago."
```

```bash
# Agent writes back what it learned
kerto learn --subject auth.go --relation caused_by --target "unbounded cache" \
  "auth.go OOM was caused by unbounded cache in the session store"

# KERTO extracts entities and edges, upserts into graph
```

The graph is the engine. The agent sees the story.

## The Data Model (FALSE Protocol)

Raw input is FALSE Protocol Occurrences, same schema as SYKLI/TAPIO/AHTI:

| Type | Source | Example |
|------|--------|---------|
| `ci.run.failed` | SYKLI | "test failed, src/auth.ts changed since last green" |
| `ci.run.passed` | SYKLI | "all tasks passed, 3.2s" |
| `context.learning` | AI agent | "parser.go OOM risk, cache must be bounded" |
| `context.decision` | AI agent | "JWT over sessions — stateless requirement" |
| `context.pattern` | KERTO | "auth.go changes → test failures (3 of last 5)" |
| `vcs.commit` | Git | "refactored auth module, 12 files changed" |

Occurrences are temporary (ring buffer, 1024 max). The graph is the permanent knowledge.

## The Compound Effect

```
Day 1:    KERTO knows your project structure and recent git history
Week 1:   KERTO knows which files break tests, which CI tasks are flaky
Month 1:  KERTO knows patterns — "every time X changes, Y breaks"
Month 6:  AI sessions feel like working with someone who knows the project
```

The longer KERTO runs, the smarter every AI session gets. Knowledge compounds.

## The Ecosystem

KERTO is the foundation layer of False Systems — the local node of a cooperative intelligence network.

```
Standalone:         kerto alone → AI agents get project memory
With SYKLI:         CI context flows in automatically (same BEAM VM)
With TAPIO + AHTI:  production context flows in → full intelligence loop
```

### The False Systems Stack

| Tool | Role | Scope |
|------|------|-------|
| **KERTO** | Local context DB — the project's story | Your laptop |
| **SYKLI** | CI as code — task orchestration | CI/CD |
| **TAPIO** | eBPF kernel observer — edge intelligence | Per node |
| **PORTTI** | K8s API watcher — cluster events | Cluster |
| **AHTI** | Central intelligence — causality + learning | Cross-system |
| **VAISTO** | Typed BEAM language — compile-time safety | Language |

Every tool speaks FALSE Protocol. Every tool fills what it knows. The Occurrence accumulates understanding.

### KERTO and AHTI: Local vs Global Memory

KERTO is the project's local memory. AHTI is the infrastructure's global memory. They complement, not compete.

```
KERTO (local, per-project)              AHTI (global, infrastructure-wide)
┌──────────────────────────┐           ┌────────────────────────────────┐
│ Git commits              │           │ TAPIO eBPF kernel events       │
│ SYKLI CI results         │──context──│ PORTTI K8s API events          │
│ AI agent learnings       │  .pattern │ ELAVA cloud resource events    │
│                          │─────────→ │ SYKLI CI occurrences via Polku │
│ 1000 nodes, 10MB         │           │ Arrow/Parquet, petgraph        │
└──────────────────────────┘           └────────────────────────────────┘
project memory                         infrastructure memory
```

**KERTO feeds patterns upstream to AHTI but never queries AHTI.** An agent queries both: KERTO for "what do I know about this codebase?" and AHTI for "what's happening in the infrastructure?"

When both hold overlapping knowledge (e.g., "auth.go changes cause failures"), KERTO is the project-level scratchpad and AHTI is the authoritative record for infrastructure-level causality. `context.pattern` occurrences from KERTO land as regular Occurrences in AHTI — they're evidence that informs pattern learning, not pre-formed causal links.

### Entry Points

```
Developer who wants AI memory     → installs KERTO → gets project memory
Developer who also wants CI       → adds SYKLI (comes with KERTO built in)
Team that needs production insight → adds TAPIO + AHTI → full loop
```

KERTO is the front door. The Vagrant of False Systems.

## Technical Foundation

- **Language**: Elixir (BEAM/OTP). Future: port core logic to Vaisto for full type safety.
- **Storage**: ETS + ETF + JSON (three-tier, proven in SYKLI)
- **Core engine**: Knowledge graph with EWMA-weighted edges
- **Protocol**: FALSE Protocol Occurrences
- **Identity**: Content-addressed (BLAKE2b)
- **IDs**: ULID (time-sortable, AHTI-compatible)
- **Distribution**: Single binary via Burrito/Bakeware
- **Install**: `brew install kerto` or `curl | bash`
- **Agent interface**: CLI (universal), MCP (native)
- **Zero config**: `kerto init` and done

### Shared BEAM Runtime

When both KERTO and SYKLI are installed, they run as OTP applications on the same BEAM VM. No HTTP, no sockets, no serialization between them — just BEAM messages. SYKLI's occurrences flow into KERTO's store natively.

## Design Principles

1. **Watch tools, not systems** — Git, SYKLI, AI agents. Not file system events, not processes.
2. **FALSE Protocol everywhere** — One schema, one store, many writers.
3. **Fill What You Know** — Each source contributes what it has authority over. No overwrites.
4. **AI-readable by default** — Structured JSON out, any agent can consume.
5. **Zero config** — `kerto init` and it works. No accounts, no servers, no setup.
6. **Compound knowledge** — Gets smarter over time. Every session enriches the next.
7. **Store outcomes, not steps** — One summary per session, not a play-by-play.
8. **Math does the forgetting** — EWMA decay, not manual eviction logic.
9. **Deduplicate on write** — Same knowledge from 20 agents = 1 entity with high confidence.

## Positioning: Equip, Don't Police

The market is moving toward managing AI output — reviewing, auditing, checkpointing what AI produced. That's the cop model: assume AI will mess up, build walls around it.

False Systems takes the opposite approach. Every tool in the stack is a **context generator that makes AI better at its job**:

| Tool | What it gives AI |
|------|-----------------|
| **KERTO** | Memory — project history, decisions, patterns |
| **SYKLI** | CI awareness — what broke, what passed, why |
| **TAPIO** | Kernel vision — network failures, OOM, syscalls |
| **AHTI** | Understanding — causality, learned patterns, root causes |

None of these are guardrails. They're all instruments that make AI see more, know more, and work better.

```
Industry: AI is dangerous → build walls around it → audit AI output
Us:       AI is blind    → give it eyes          → enrich AI input
```

The bet: if you give AI the right context, you don't need to police its output. The code is better because the input was better. Trust over control. Context over checkpoints.

---

**False Systems** | *kerto* — give your project a story.
