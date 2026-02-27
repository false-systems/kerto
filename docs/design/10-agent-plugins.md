# KERTO — Agent Plugin Design

## ADR-010: Agent Plugins — Local Log Ingestion per Agent

**Status:** Proposed
**Context:** Kerto currently receives knowledge through explicit calls (`kerto_learn`, `kerto_observe`) or CI/git hooks. But AI agents leave rich local traces — conversation histories, tool calls, error logs, completion patterns — that go unread. A plugin system can passively ingest these logs, closing the feedback loop without requiring the agent to explicitly report.

## The Problem

Today, knowledge enters Kerto only when:
1. Git commits happen (`vcs.commit`)
2. CI runs (`ci.run.failed/passed`)
3. The agent explicitly calls `kerto_learn` or `kerto_observe`

This misses the majority of what an agent *does*:
- Files it read but didn't modify
- Approaches it tried and abandoned
- Errors it encountered from tools
- Patterns in which files it keeps revisiting
- Conversation context that never gets summarized

Agents forget. And they forget to tell Kerto what they learned.

## The Solution: Agent Plugins

Each AI agent gets a plugin that reads its local state and emits occurrences into the standard pipeline.

```
Agent local logs
     ↓
Plugin (reader + parser)
     ↓
Occurrences (standard types)
     ↓
Extraction (L1) → Graph ops → Engine (L2)
```

### Plugin Interface

A plugin implements one behaviour:

```elixir
@callback agent_name() :: String.t()
@callback scan(last_sync :: DateTime.t() | nil) :: [Occurrence.t()]
```

- `agent_name/0` — identifies the source (e.g., `"claude"`, `"cursor"`, `"copilot"`)
- `scan/1` — reads local state since last sync, returns occurrences

The engine calls `scan/1` periodically or on demand. Plugins are stateless readers — they don't modify agent state.

### Example Plugins

**Claude Code** (`kerto-plugin-claude`):
- Reads `~/.claude/projects/` conversation state
- Extracts: files touched, errors encountered, tools called
- Emits: `agent.file_read`, `agent.tool_error`, `agent.session_end`

**Cursor** (`kerto-plugin-cursor`):
- Reads Cursor's local session/workspace state
- Extracts: files edited, completions accepted/rejected, chat history
- Emits: `agent.file_edit`, `agent.completion`, `agent.session_end`

**Copilot** (`kerto-plugin-copilot`):
- Reads VS Code extension logs, completion acceptance rates
- Extracts: completion patterns, frequently suggested files
- Emits: `agent.completion`, `agent.suggestion_pattern`

**Custom / Local logs** (`kerto-plugin-logs`):
- Reads application logs from configurable paths
- Extracts: error patterns, stack traces, recurring warnings
- Emits: `app.error`, `app.warning_pattern`

### Occurrence Types

Plugins reuse existing types where possible and introduce new ones only when needed:

| Occurrence Type | Source | Extracted Knowledge |
|----------------|--------|-------------------|
| `agent.file_read` | Agent read a file without modifying | Implicit dependency signal |
| `agent.tool_error` | Agent's tool call failed | Error patterns, broken tooling |
| `agent.session_end` | Session completed (already exists) | Session summary |
| `agent.approach_abandoned` | Agent tried something and reverted | "Tried X, didn't work because Y" |
| `agent.completion` | Completion accepted/rejected | Code pattern preferences |
| `app.error` | Application log error | Runtime error → file relationships |
| `app.warning_pattern` | Recurring log warning | Degradation signals |

### New Extractors

Each new occurrence type gets an extractor in L1:

- `Extractor.FileRead` — creates `:file` nodes with low confidence (0.1), no relationships unless paired with other signals
- `Extractor.ApproachAbandoned` — creates `:tried_failed` relationships, high value
- `Extractor.AppError` — creates `:error` nodes, `:caused_by` relationships from stack traces

### Architecture Placement

```
Level 0: graph/           — unchanged
Level 1: ingestion/       — new extractors for new occurrence types
         rendering/       — unchanged
Level 2: engine/          — unchanged (plugins feed standard ingest/2)
Level 3: mesh/            — plugins are local-only, but their occurrences sync via mesh
Level 4: interface/       — plugin registry, scan scheduling
         plugins/         — plugin implementations (one module per agent)
```

Plugins sit at L4 (they do IO — reading files from disk). They produce L1 occurrences. The rest of the pipeline is untouched.

### Plugin Registry

```elixir
# .kerto/plugins.exs or config
[
  {Kerto.Plugin.Claude, path: "~/.claude/projects/"},
  {Kerto.Plugin.Logs, paths: ["logs/app.log", "/var/log/myapp.log"]}
]
```

The engine loads configured plugins and runs `scan/1` on:
- Daemon startup (catch up on what happened while Kerto was off)
- Periodic interval (configurable, default 5 min)
- Explicit trigger (`kerto scan`)

### Privacy & Security

- Plugins only read, never write to agent state
- Conversation content is **not** stored — only structural signals (file names, error types, tool names)
- Plugin config is local (`.kerto/plugins.exs` is gitignored)
- Each plugin declares what it reads in its `@moduledoc`

## Design Decisions

### Why plugins instead of agent-side hooks?

Hooks require each agent to integrate with Kerto. Plugins let Kerto pull from any agent's local state without the agent knowing or caring. Works with closed-source agents that don't support hooks.

### Why periodic scan instead of file watchers?

Simpler. Agent log formats change between versions. A periodic scan with `last_sync` is resilient to format changes, restarts, and gaps. File watchers add complexity for marginal latency improvement — agent logs aren't time-critical.

### Why low confidence for passive signals?

Reading a file (0.1) is weak evidence compared to a CI failure (0.7) or explicit learning (0.8). Passive signals accumulate over time — if an agent reads `auth.go` in 20 sessions, EWMA converges upward naturally. The graph self-corrects.

## Implementation Order

1. Define `Kerto.Plugin` behaviour
2. Implement `Kerto.Plugin.Claude` (we use it, dog-food first)
3. Add scan scheduling to engine/daemon
4. Add `kerto scan` command
5. Implement `Kerto.Plugin.Logs` (generic log reader)
6. Community plugins for Cursor, Copilot, etc.
