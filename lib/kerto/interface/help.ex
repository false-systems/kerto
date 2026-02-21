defmodule Kerto.Interface.Help do
  @moduledoc """
  CLI help text renderer.
  """

  @specs %{
    "status" => %{
      description: "Show graph statistics (nodes, relationships, occurrences)",
      usage: "kerto status [--json]",
      flags: [],
      examples: ["kerto status", "kerto status --json"]
    },
    "context" => %{
      description: "Query an entity and render its knowledge context",
      usage: "kerto context <name> [flags]",
      flags: [
        {"--kind <kind>",
         "Node kind: file, module, pattern, decision, error, concept (default: file)"},
        {"--depth <n>", "Traversal depth (default: 1)"},
        {"--min-weight <f>", "Minimum relationship weight (default: 0.0)"}
      ],
      examples: ["kerto context auth.go", "kerto context api --kind module --depth 2"]
    },
    "learn" => %{
      description: "Record a learning occurrence (what you learned about the codebase)",
      usage: "kerto learn <evidence> --subject <name> [flags]",
      flags: [
        {"--subject <name>", "Subject entity name (required)"},
        {"--subject-kind <kind>", "Subject kind (default: file)"},
        {"--target <name>", "Target entity name (optional relationship)"},
        {"--target-kind <kind>", "Target kind (default: file)"},
        {"--relation <rel>", "Relationship type (default: learned)"},
        {"--confidence <f>", "Confidence 0.0-1.0 (default: 0.8)"}
      ],
      examples: [
        ~s(kerto learn "auth.go handles authentication" --subject auth.go),
        ~s(kerto learn "auth depends on session" --subject auth.go --target session.go --relation depends_on)
      ]
    },
    "decide" => %{
      description: "Record an architectural decision",
      usage: "kerto decide <evidence> --subject <name> [flags]",
      flags: [
        {"--subject <name>", "Subject entity name (required)"},
        {"--subject-kind <kind>", "Subject kind (default: decision)"},
        {"--target <name>", "Target entity name (optional)"},
        {"--target-kind <kind>", "Target kind (default: file)"},
        {"--confidence <f>", "Confidence 0.0-1.0 (default: 0.8)"}
      ],
      examples: [~s(kerto decide "use JWT for auth" --subject auth-strategy)]
    },
    "ingest" => %{
      description: "Manually ingest a raw occurrence (JSON from stdin)",
      usage: "kerto ingest --type <type>",
      flags: [{"--type <type>", "Occurrence type (e.g. vcs.commit, ci.run.failed)"}],
      examples: [~s(echo '{"files":["a.go"]}' | kerto ingest --type ci.run.failed)]
    },
    "graph" => %{
      description: "Dump the full knowledge graph",
      usage: "kerto graph [--format json|dot]",
      flags: [{"--format <fmt>", "Output format: json or dot (default: json)"}],
      examples: ["kerto graph", "kerto graph --format dot | dot -Tpng -o graph.png"]
    },
    "decay" => %{
      description: "Trigger manual EWMA decay on all nodes and relationships",
      usage: "kerto decay [--factor <f>]",
      flags: [{"--factor <f>", "Decay factor 0.0-1.0 (default: 0.95)"}],
      examples: ["kerto decay", "kerto decay --factor 0.5"]
    },
    "weaken" => %{
      description: "Weaken a specific relationship",
      usage: "kerto weaken --source <name> --relation <rel> --target <name> [flags]",
      flags: [
        {"--source <name>", "Source entity name"},
        {"--source-kind <kind>", "Source kind (default: file)"},
        {"--relation <rel>", "Relationship type"},
        {"--target <name>", "Target entity name"},
        {"--target-kind <kind>", "Target kind (default: file)"},
        {"--factor <f>", "Weakening factor (default: 0.5)"}
      ],
      examples: [~s(kerto weaken --source auth.go --relation breaks --target test)]
    },
    "delete" => %{
      description: "Hard-remove a node or relationship from the graph",
      usage: "kerto delete --node <name> [--kind <kind>]",
      flags: [
        {"--node <name>", "Node name to delete"},
        {"--kind <kind>", "Node kind (default: file)"},
        {"--source <name>", "Source name (for relationship delete)"},
        {"--relation <rel>", "Relationship type (for relationship delete)"},
        {"--target <name>", "Target name (for relationship delete)"},
        {"--source-kind <kind>", "Source kind (default: file)"},
        {"--target-kind <kind>", "Target kind (default: file)"}
      ],
      examples: [
        "kerto delete --node auth.go --kind file",
        "kerto delete --source auth.go --relation breaks --target test"
      ]
    },
    "init" => %{
      description: "Initialize .kerto/ directory, .mcp.json, and .gitignore",
      usage: "kerto init",
      flags: [],
      examples: ["kerto init"]
    },
    "start" => %{
      description: "Start the kerto daemon in the background",
      usage: "kerto start",
      flags: [],
      examples: ["kerto start"]
    },
    "stop" => %{
      description: "Stop the running kerto daemon",
      usage: "kerto stop",
      flags: [],
      examples: ["kerto stop"]
    },
    "mcp" => %{
      description: "Start MCP server (JSON-RPC over stdio, used by Claude Code)",
      usage: "kerto mcp",
      flags: [],
      examples: ["kerto mcp"]
    }
  }

  @spec render(String.t() | nil) :: String.t()
  def render(nil), do: render_global()

  def render(command) do
    case Map.get(@specs, command) do
      nil -> "Unknown command: #{command}\n\n" <> render_global()
      spec -> render_command(command, spec)
    end
  end

  defp render_global do
    commands =
      @specs
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join("\n", fn {name, spec} ->
        "  #{String.pad_trailing(name, 10)} #{spec.description}"
      end)

    """
    Usage: kerto <command> [flags]

    Commands:
    #{commands}

    Run 'kerto <command> --help' for command-specific help.\
    """
  end

  defp render_command(_name, spec) do
    parts = ["Usage: #{spec.usage}", "", spec.description]

    parts =
      if spec.flags != [] do
        flags =
          Enum.map_join(spec.flags, "\n", fn {flag, desc} ->
            "  #{String.pad_trailing(flag, 24)} #{desc}"
          end)

        parts ++ ["", "Flags:", flags]
      else
        parts
      end

    parts =
      if spec.examples != [] do
        examples = Enum.map_join(spec.examples, "\n", &("  " <> &1))
        parts ++ ["", "Examples:", examples]
      else
        parts
      end

    Enum.join(parts, "\n")
  end
end
