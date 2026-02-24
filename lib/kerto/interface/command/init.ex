defmodule Kerto.Interface.Command.Init do
  @moduledoc "Initializes .kerto/ directory, .mcp.json, and .gitignore entries."

  alias Kerto.Interface.Command.Bootstrap
  alias Kerto.Interface.Response

  @kerto_dir ".kerto"
  @mcp_json ".mcp.json"
  @gitignore ".gitignore"
  @gitignore_entries [
    ".kerto/graph.etf",
    ".kerto/kerto.sock",
    ".kerto/kerto.pid",
    ".kerto/kerto.log",
    ".kerto/AGENT.md",
    ".kerto/session"
  ]

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, _args) do
    File.mkdir_p!(@kerto_dir)
    write_mcp_json()
    update_gitignore()
    write_agent_md()

    case Bootstrap.execute(engine, %{}) do
      %{ok: true, data: msg} ->
        Response.success("Initialized #{@kerto_dir}/ and #{@mcp_json} (#{msg})")

      _ ->
        Response.success("Initialized #{@kerto_dir}/ and #{@mcp_json}")
    end
  end

  defp write_mcp_json do
    kerto_server = %{"command" => "kerto", "args" => ["mcp"]}

    existing =
      case File.read(@mcp_json) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} -> map
            {:error, _} -> %{}
          end

        {:error, _} ->
          %{}
      end

    servers =
      existing
      |> Map.get("mcpServers", %{})
      |> Map.put("kerto", kerto_server)

    merged = Map.put(existing, "mcpServers", servers)
    File.write!(@mcp_json, Jason.encode!(merged, pretty: true) <> "\n")
  end

  @agent_md_path ".kerto/AGENT.md"

  defp write_agent_md do
    unless File.exists?(@agent_md_path) do
      File.write!(@agent_md_path, """
      # Kerto Agent Learning Conventions

      > This file tells AI agents when to record knowledge into the Kerto graph.
      > It is gitignored — local convention, not project configuration.

      ## When to call `kerto_learn`

      - Bug patterns: "auth.go OOM was caused by unbounded session cache"
      - Error causes: "timeout in deploy was caused by missing health check"
      - Surprising dependencies: "parser.go silently depends on locale settings"
      - Tried-and-failed approaches: "Redis caching didn't work because of key size limits"

      ## When to call `kerto_decide`

      - Design choices: "chose JWT over sessions for stateless scaling"
      - Algorithm selections: "switched from BFS to Dijkstra for weighted paths"
      - Rejected alternatives: "considered MongoDB but chose Postgres for ACID"

      ## When to call `kerto_observe`

      - Before session end: 1-3 sentence summary of what was done + central files
      - After completing a significant task or investigation
      - Example: `kerto_observe(summary: "Fixed OOM in auth by adding LRU cache", files: ["auth.go", "cache.go"])`

      ## What NOT to record

      - Files you only read (not modified or central to findings)
      - Formatting-only changes
      - Things already documented in CLAUDE.md or README
      - Trivial fixes (typos, import ordering)
      """)
    end
  end

  defp update_gitignore do
    existing =
      case File.read(@gitignore) do
        {:ok, content} -> content
        {:error, _} -> ""
      end

    lines = String.split(existing, "\n")

    new_entries =
      @gitignore_entries
      |> Enum.reject(&(&1 in lines))

    if new_entries != [] do
      suffix = if String.ends_with?(existing, "\n") or existing == "", do: "", else: "\n"
      File.write!(@gitignore, existing <> suffix <> Enum.join(new_entries, "\n") <> "\n")
    end
  end
end
