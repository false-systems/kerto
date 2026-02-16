# KERTO — FALSE Protocol Occurrence Design

## Overview

KERTO operates in the `context.*` namespace of FALSE Protocol. It consumes occurrences from external sources (SYKLI, Git, AI agents) and produces its own pattern-detection occurrences.

### Type Hierarchy

```
context.*                    — KERTO's domain
├── context.learning         — AI agent learned something (consumed)
├── context.decision         — AI agent recorded a decision (consumed)
├── context.pattern          — KERTO detected a recurring pattern (produced)
└── context.query            — KERTO answered a query (produced, for audit trail)

ci.*                         — SYKLI's domain (consumed by KERTO)
├── ci.run.failed
└── ci.run.passed

vcs.*                        — Git's domain (consumed by KERTO)
└── vcs.commit
```

## Consumed Occurrence Types

### ci.run.failed (from SYKLI)

SYKLI already produces this. KERTO consumes it as-is. Documented here for extraction reference.

```json
{
  "id": "01JKXA...",
  "timestamp": "2026-02-13T14:30:00Z",
  "source": "sykli",
  "type": "ci.run.failed",
  "severity": "error",
  "outcome": "failure",

  "context": {
    "project": "my-project"
  },

  "error": {
    "code": "CI_RUN_FAILED",
    "what_failed": "1 task failed: test",
    "why_it_matters": "blocks build, deploy",
    "possible_causes": ["src/auth.go changed and matches test inputs"],
    "suggested_fix": "Review recent changes to src/auth.go"
  },

  "reasoning": {
    "summary": "test failed — src/auth.go changed",
    "explanation": "The test task failed after src/auth.go was modified. This file is in the test task's input set. The last successful run was at commit abc123.",
    "confidence": 0.8,
    "tasks": {
      "test": {
        "changed_files": ["src/auth.go"],
        "explanation": "matches test inputs"
      }
    }
  },

  "history": {
    "steps": [
      {"description": "lint", "status": "passed", "duration_ms": 2186},
      {"description": "test", "status": "failed", "duration_ms": 591}
    ],
    "duration_ms": 3112,
    "recent_outcomes": {"test": ["pass", "pass", "fail"]},
    "regression": {"is_new_failure": true, "tasks": ["test"]}
  },

  "ci_data": {
    "git": {
      "sha": "4b4a354",
      "branch": "main",
      "changed_files": ["src/auth.go", "src/auth_test.go"]
    },
    "summary": {"passed": 1, "failed": 1, "cached": 0, "skipped": 0},
    "tasks": [
      {
        "name": "test",
        "status": "failed",
        "command": "go test ./...",
        "duration_ms": 591,
        "inputs": ["**/*.go"],
        "log": ".sykli/logs/01JKXA.../test.log"
      }
    ]
  }
}
```

**KERTO Extraction:**
- Nodes: each file in `ci_data.git.changed_files` → `:file`, each failed task → `:module` (test suite)
- Relationships: changed_file → failed_task = `:breaks` with confidence from `reasoning.confidence`
- Reinforces existing patterns if this file has broken this test before

### ci.run.passed (from SYKLI)

```json
{
  "id": "01JKXB...",
  "timestamp": "2026-02-13T14:35:00Z",
  "source": "sykli",
  "type": "ci.run.passed",
  "severity": "info",
  "outcome": "success",

  "context": {
    "project": "my-project"
  },

  "ci_data": {
    "git": {
      "sha": "5c5b465",
      "branch": "main",
      "changed_files": ["src/auth.go"]
    },
    "summary": {"passed": 3, "failed": 0, "cached": 0, "skipped": 0},
    "tasks": [
      {"name": "lint", "status": "passed", "duration_ms": 1200},
      {"name": "test", "status": "passed", "duration_ms": 800},
      {"name": "build", "status": "passed", "duration_ms": 3500}
    ]
  }
}
```

**KERTO Extraction:**
- Nodes: each file in `changed_files` → `:file` (low confidence boost, 0.1)
- Relationships: if a `:breaks` relationship exists between this file and a test that now passes, *reduce* the relationship's confidence (counter-evidence)
- This prevents stale `:breaks` edges from persisting after a fix

### vcs.commit (from Git hooks)

```json
{
  "id": "01JKXC...",
  "timestamp": "2026-02-13T14:40:00Z",
  "source": "git",
  "type": "vcs.commit",
  "severity": "info",
  "outcome": "success",

  "context": {
    "project": "my-project"
  },

  "data": {
    "sha": "abc1234def5678",
    "branch": "main",
    "author": "yair",
    "message": "refactor: extract auth interface",
    "changed_files": [
      "src/auth.go",
      "src/auth_interface.go",
      "src/auth_test.go"
    ],
    "insertions": 45,
    "deletions": 12
  }
}
```

**KERTO Extraction:**
- Nodes: each file in `changed_files` → `:file`
- Relationships: all pairs of changed files → `:often_changes_with` at confidence 0.5
- Co-change detection: files that frequently change together build strong `:often_changes_with` edges over time

### context.learning (from AI agents)

This is KERTO's primary write interface from agents.

```json
{
  "id": "01JKXD...",
  "timestamp": "2026-02-13T15:00:00Z",
  "source": "agent",
  "type": "context.learning",
  "severity": "info",
  "outcome": "success",

  "context": {
    "project": "my-project",
    "agent": "claude-code",
    "session_id": "2026-02-13-abc123"
  },

  "data": {
    "subject": {
      "name": "src/parser.go",
      "kind": "file"
    },
    "learning": "The cache in parser.go must be bounded. Unbounded cache caused OOM in production (January incident).",
    "relation": "caused_by",
    "target": {
      "name": "OOM",
      "kind": "error"
    },
    "confidence": 0.9
  }
}
```

**KERTO Extraction:**
- Nodes: `data.subject` → Knowledge Node, `data.target` → Knowledge Node
- Relationship: subject → target with `data.relation` at `data.confidence`
- Evidence: `data.learning` appended to the Relationship's evidence list (accumulates, not overwrites — if Agent A learns "cache must be bounded" and Agent B learns "tokens expire after 1h", both are kept)

**CLI mapping:**
```bash
kerto learn --subject "src/parser.go" --subject-kind file \
           --relation caused_by \
           --target "OOM" --target-kind error \
           --confidence 0.9 \
           "The cache in parser.go must be bounded. Unbounded cache caused OOM."
```

### context.decision (from AI agents)

Records an architectural or design decision.

```json
{
  "id": "01JKXE...",
  "timestamp": "2026-02-13T15:10:00Z",
  "source": "agent",
  "type": "context.decision",
  "severity": "info",
  "outcome": "success",

  "context": {
    "project": "my-project",
    "agent": "claude-code",
    "session_id": "2026-02-13-abc123"
  },

  "data": {
    "subject": {
      "name": "auth module",
      "kind": "module"
    },
    "decision": "Use JWT over sessions for authentication. Stateless requirement from API gateway design. Sessions would require sticky routing.",
    "alternatives_considered": [
      "Session-based auth (rejected: requires sticky routing)",
      "OAuth2 only (rejected: too complex for internal services)"
    ],
    "relation": "decided",
    "target": {
      "name": "JWT",
      "kind": "concept"
    },
    "confidence": 0.95
  }
}
```

**KERTO Extraction:**
- Nodes: `data.subject` → Knowledge Node (`:module`), `data.target` → Knowledge Node (`:concept`)
- Relationship: subject → target with `:decided` at `data.confidence`
- Also creates `:tried_failed` relationships for rejected alternatives if they have enough structure

**CLI mapping:**
```bash
kerto decide --subject "auth module" --subject-kind module \
            --target "JWT" --target-kind concept \
            --confidence 0.95 \
            "Use JWT over sessions. Stateless requirement from API gateway design."
```

## Produced Occurrence Types

### context.pattern (produced by KERTO)

When KERTO detects a recurring pattern through graph analysis (e.g., a `:breaks` edge reinforced 5+ times), it produces a pattern occurrence.

```json
{
  "id": "01JKXF...",
  "timestamp": "2026-02-13T18:00:00Z",
  "source": "kerto",
  "type": "context.pattern",
  "severity": "warning",
  "outcome": "success",

  "context": {
    "project": "my-project"
  },

  "reasoning": {
    "summary": "src/auth.go changes consistently break login tests",
    "explanation": "Over the last 30 days, 5 out of 7 changes to src/auth.go resulted in login test failures. The :breaks relationship between auth.go and login_test has reached 0.87 confidence. This pattern has been stable for 3 weeks.",
    "confidence": 0.87,
    "causal_chain": [
      {"occurrence_id": "01JKX1...", "summary": "ci.run.failed: auth.go changed, test failed"},
      {"occurrence_id": "01JKX2...", "summary": "ci.run.failed: auth.go changed, test failed"},
      {"occurrence_id": "01JKX5...", "summary": "ci.run.failed: auth.go changed, test failed"}
    ],
    "patterns_matched": ["high_confidence_breaks"]
  },

  "data": {
    "pattern_type": "recurring_breakage",
    "source_node": {
      "name": "src/auth.go",
      "kind": "file",
      "id": "a1b2c3..."
    },
    "target_node": {
      "name": "login_test",
      "kind": "module",
      "id": "d4e5f6..."
    },
    "relation": "breaks",
    "weight": 0.87,
    "observations": 5,
    "window_days": 30
  }
}
```

**When produced:**
- After each decay cycle, KERTO scans for relationships that have crossed a significance threshold (e.g., observations >= 5 AND weight >= 0.7)
- Only produced once per pattern — tracked by `{source_node, relation, target_node}` hash
- Re-produced if the pattern strengthens significantly (weight increases by > 0.1)

### context.query (produced by KERTO, optional audit trail)

When an agent queries KERTO, the query and response can be logged as an occurrence for traceability.

```json
{
  "id": "01JKXG...",
  "timestamp": "2026-02-13T15:30:00Z",
  "source": "kerto",
  "type": "context.query",
  "severity": "debug",
  "outcome": "success",

  "context": {
    "project": "my-project",
    "agent": "claude-code"
  },

  "data": {
    "query": "context auth.go",
    "nodes_returned": 4,
    "relationships_returned": 7,
    "response_summary": "auth.go is a high-risk file. Changes break login_test.go (82% confidence)..."
  }
}
```

**When produced:** Only when explicitly enabled (debug/audit mode). Not produced by default — avoids noise.

## Elixir Struct Definitions

```elixir
defmodule Kerto.Ingestion.Occurrence do
  @enforce_keys [:id, :timestamp, :source, :type, :severity, :outcome]
  defstruct [
    :id,           # ULID string
    :timestamp,    # DateTime
    :source,       # :git | :sykli | :agent | :kerto
    :type,         # String, e.g., "ci.run.failed"
    :severity,     # :debug | :info | :warning | :error | :critical
    :outcome,      # :success | :failure | :timeout | :in_progress | :unknown
    context: %{},  # %{project: String, agent: String, ...}
    error: nil,    # %Error{} | nil
    reasoning: nil,# %Reasoning{} | nil
    history: nil,  # %History{} | nil
    data: %{}      # type-specific payload
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    timestamp: DateTime.t(),
    source: :git | :sykli | :agent | :kerto,
    type: String.t(),
    severity: :debug | :info | :warning | :error | :critical,
    outcome: :success | :failure | :timeout | :in_progress | :unknown,
    context: map(),
    error: Error.t() | nil,
    reasoning: Reasoning.t() | nil,
    history: History.t() | nil,
    data: map()
  }
end

defmodule Kerto.Ingestion.Occurrence.Error do
  @enforce_keys [:code, :what_failed]
  defstruct [
    :code,              # String, UPPER_SNAKE
    :what_failed,       # String, plain English
    :why_it_matters,    # String | nil
    possible_causes: [],# [String]
    :suggested_fix      # String | nil
  ]
end

defmodule Kerto.Ingestion.Occurrence.Reasoning do
  @enforce_keys [:summary, :explanation, :confidence]
  defstruct [
    :summary,           # String, one line
    :explanation,       # String, full narrative
    :confidence,        # float 0.0..1.0
    causal_chain: [],   # [%{occurrence_id: String, summary: String}]
    patterns_matched: []# [String]
  ]
end

defmodule Kerto.Ingestion.Occurrence.History do
  defstruct [
    steps: [],          # [%{description: String, status: String, duration_ms: integer}]
    :duration_ms,       # integer | nil
    recent_outcomes: %{},# %{task_name => [String]}
    regression: nil     # %{is_new_failure: boolean, tasks: [String]} | nil
  ]
end
```

## Extraction Rules Summary

| Occurrence Type | Nodes Extracted | Relationships Extracted | Confidence Source |
|----------------|-----------------|------------------------|-------------------|
| `ci.run.failed` | changed files (`:file`), failed tasks (`:module`) | file → task = `:breaks` | `reasoning.confidence` or 0.7 default |
| `ci.run.passed` | changed files (`:file`) | counter-evidence: reduce existing `:breaks` weights | 0.1 (weak negative signal) |
| `vcs.commit` | changed files (`:file`) | file pairs → `:often_changes_with` | 0.5 per co-occurrence |
| `context.learning` | subject (any kind), target (any kind) | subject → target with specified relation | `data.confidence` or 0.8 default |
| `context.decision` | subject (any kind), target (any kind) | subject → target = `:decided` | `data.confidence` or 0.9 default |

## Fill What You Know

Each source fills the fields it has authority over:

| Source | Fills | Skips |
|--------|-------|-------|
| **Git** | `data` (sha, files, message) | `error`, `reasoning`, `history` |
| **SYKLI** | `error`, `reasoning`, `history`, `ci_data` | nothing — SYKLI fills everything it knows |
| **Agent** | `data` (subject, target, learning/decision) | `error`, `history` |
| **KERTO** | `reasoning` (for patterns), `data` | `error` (KERTO doesn't observe errors directly) |

KERTO never overwrites fields from other sources. It adds Reasoning to patterns it detects. The Occurrence accumulates understanding from multiple sources over time.
