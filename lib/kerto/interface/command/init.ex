defmodule Kerto.Interface.Command.Init do
  @moduledoc "Initializes .kerto/ directory, .mcp.json, and .gitignore entries."

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

  @claude_dir ".claude"
  @claude_hooks_dir ".claude/hooks"
  @claude_settings ".claude/settings.json"

  @spec execute(atom(), map()) :: Response.t()
  def execute(_engine, _args) do
    File.mkdir_p!(@kerto_dir)
    write_mcp_json()
    update_gitignore()
    write_post_commit_hook()
    write_claude_hooks()
    write_agent_md()
    Response.success("Initialized #{@kerto_dir}/ and #{@mcp_json}")
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

  defp write_claude_hooks do
    File.mkdir_p!(@claude_hooks_dir)
    write_pre_tool_use_hook()
    write_post_tool_use_hook()
    write_stop_hook()
    update_claude_settings()
  end

  defp write_pre_tool_use_hook do
    path = Path.join(@claude_hooks_dir, "pre_tool_use.sh")

    File.write!(path, """
    #!/bin/sh
    # Kerto auto-learning: inject hints before file operations
    INPUT=$(cat)
    TOOL=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | cut -d'"' -f4)

    case "$TOOL" in
      Write|Edit|MultiEdit|Read)
        FILE=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
        [ -n "$FILE" ] && kerto hint --files "$FILE" 2>/dev/null || true
        ;;
    esac
    """)

    File.chmod!(path, 0o755)
  end

  defp write_post_tool_use_hook do
    path = Path.join(@claude_hooks_dir, "post_tool_use.sh")

    File.write!(path, """
    #!/bin/sh
    # Kerto auto-learning: track file edits and tool errors from agent tools
    INPUT=$(cat)
    TOOL=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | cut -d'"' -f4)

    case "$TOOL" in
      Write|Edit|MultiEdit)
        FILE=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$FILE" ]; then
          kerto ingest --type agent.file_edit --data "{\\"file\\":\\"$FILE\\",\\"tool\\":\\"$TOOL\\"}" || true
          SESSION=$(cat .kerto/session 2>/dev/null)
          [ -n "$SESSION" ] && kerto track-edit --session "$SESSION" --file "$FILE" 2>/dev/null || true
        fi
        ;;
      Bash)
        OUTPUT=$(echo "$INPUT" | grep -o '"output":"[^"]*"' | head -1 | cut -d'"' -f4)
        EXIT=$(echo "$INPUT" | grep -o '"exit_code":[0-9]*' | head -1 | cut -d':' -f2)
        if [ "$EXIT" != "0" ] && [ -n "$OUTPUT" ]; then
          kerto ingest --type agent.tool_error --data "{\\"error\\":\\"$(echo "$OUTPUT" | head -c 200)\\",\\"tool\\":\\"Bash\\"}" || true
        fi
        ;;
    esac
    """)

    File.chmod!(path, 0o755)
  end

  defp write_stop_hook do
    path = Path.join(@claude_hooks_dir, "stop.sh")

    File.write!(path, """
    #!/bin/sh
    # Kerto auto-learning: capture session context from git signals
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    FILES=$(git diff --name-only HEAD 2>/dev/null | head -20)
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | head -20)
    COMMITS=$(git log --oneline -5 2>/dev/null)
    STAT=$(git diff --stat HEAD 2>/dev/null | tail -1)

    # Build file list (modified + uncommitted, deduplicated)
    ALL_FILES=$(printf '%s\\n%s' "$FILES" "$(echo "$UNCOMMITTED" | awk '{print $NF}')" | sort -u | grep -v '^$' | tr '\\n' ',' | sed 's/,$//')

    # Build summary from commits (most informative signal)
    if [ -n "$COMMITS" ]; then
      SUMMARY="[$BRANCH] $(echo "$COMMITS" | head -3 | cut -d' ' -f2- | tr '\\n' '; ' | sed 's/; $//')"
    else
      SUMMARY="[$BRANCH] Work in progress"
    fi

    # Append stats if available
    if [ -n "$STAT" ]; then
      SUMMARY="$SUMMARY ($STAT)"
    fi

    # Flush session buffer for co-edit relationships
    SESSION=$(cat .kerto/session 2>/dev/null)
    [ -n "$SESSION" ] && kerto flush-session --session "$SESSION" 2>/dev/null || true

    if [ -n "$ALL_FILES" ]; then
      kerto observe --summary "$SUMMARY" --files "$ALL_FILES" || true
    fi
    """)

    File.chmod!(path, 0o755)
  end

  defp update_claude_settings do
    File.mkdir_p!(@claude_dir)

    existing =
      case File.read(@claude_settings) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} -> map
            {:error, _} -> %{}
          end

        {:error, _} ->
          %{}
      end

    hooks = Map.get(existing, "hooks", %{})

    post_tool_use = Map.get(hooks, "PostToolUse", [])

    kerto_ptu = %{
      "type" => "command",
      "command" => "sh .claude/hooks/post_tool_use.sh"
    }

    post_tool_use =
      if Enum.any?(post_tool_use, &(&1["command"] == kerto_ptu["command"])),
        do: post_tool_use,
        else: post_tool_use ++ [kerto_ptu]

    stop = Map.get(hooks, "Stop", [])

    kerto_stop = %{
      "type" => "command",
      "command" => "sh .claude/hooks/stop.sh"
    }

    stop =
      if Enum.any?(stop, &(&1["command"] == kerto_stop["command"])),
        do: stop,
        else: stop ++ [kerto_stop]

    pre_tool_use = Map.get(hooks, "PreToolUse", [])

    kerto_pre = %{
      "type" => "command",
      "command" => "sh .claude/hooks/pre_tool_use.sh"
    }

    pre_tool_use =
      if Enum.any?(pre_tool_use, &(&1["command"] == kerto_pre["command"])),
        do: pre_tool_use,
        else: pre_tool_use ++ [kerto_pre]

    hooks =
      hooks
      |> Map.put("PreToolUse", pre_tool_use)
      |> Map.put("PostToolUse", post_tool_use)
      |> Map.put("Stop", stop)

    merged = Map.put(existing, "hooks", hooks)
    File.write!(@claude_settings, Jason.encode!(merged, pretty: true) <> "\n")
  end

  defp write_post_commit_hook do
    hooks_dir = ".git/hooks"

    if File.dir?(".git") do
      File.mkdir_p!(hooks_dir)
      path = Path.join(hooks_dir, "post-commit")

      File.write!(path, """
      #!/bin/sh
      # Kerto auto-learning: feed commit data into the knowledge graph
      HASH=$(git rev-parse HEAD)
      MESSAGE=$(git log -1 --pretty=%s "$HASH")
      FILES=$(git diff-tree --no-commit-id --name-only -r "$HASH" | tr '\\n' ',' | sed 's/,$//')
      JSON=$(printf '{"files":[%s],"message":"%s"}' "$(echo "$FILES" | sed 's/[^,]*/\"&\"/g')" "$MESSAGE")
      kerto ingest --type vcs.commit --data "$JSON" || true
      """)

      File.chmod!(path, 0o755)
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
