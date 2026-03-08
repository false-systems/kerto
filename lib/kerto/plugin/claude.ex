defmodule Kerto.Plugin.Claude do
  @moduledoc """
  Passive learning from Claude Code conversation state.

  Reads `~/.claude/projects/` JSONL conversation files and extracts:
  - File reads/edits → `agent.file_read` occurrences
  - Tool errors → `agent.tool_error` occurrences

  Claude Code stores conversations as JSONL files in `~/.claude/projects/`.
  Each line is a JSON object with `type`, `timestamp`, `sessionId`, and
  `message` fields. Tool uses appear in `assistant` messages as
  `tool_use` content blocks; results appear in `user` messages as
  `tool_result` content blocks matched by `tool_use_id`.
  """

  @behaviour Kerto.Plugin

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.ULID

  @file_tools ~w(Read Edit Write)
  @projects_dir "~/.claude/projects"

  @impl true
  def agent_name, do: "claude"

  @impl true
  @spec scan(String.t() | nil) :: [Occurrence.t()]
  def scan(last_sync), do: scan(last_sync, [])

  @doc """
  Scan with options. Accepts `:projects_dir` to override the default path.
  """
  @spec scan(String.t() | nil, keyword()) :: [Occurrence.t()]
  def scan(last_sync, opts) do
    cutoff_ms = ulid_to_ms(last_sync)
    dir = Keyword.get(opts, :projects_dir, projects_dir())

    dir
    |> list_jsonl_files(cutoff_ms)
    |> Enum.flat_map(&parse_conversation/1)
  end

  # --- Internal ---

  @doc false
  def projects_dir, do: Path.expand(@projects_dir)

  defp list_jsonl_files(base, cutoff_ms) do
    if File.dir?(base) do
      base
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(base, &1)))
      |> Enum.flat_map(fn project_dir ->
        full = Path.join(base, project_dir)

        full
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.map(&Path.join(full, &1))
        |> Enum.filter(fn path -> file_modified_after?(path, cutoff_ms) end)
      end)
    else
      []
    end
  end

  defp file_modified_after?(_path, nil), do: true

  defp file_modified_after?(path, cutoff_ms) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime * 1000 >= cutoff_ms
      _ -> false
    end
  end

  defp parse_conversation(path) do
    path
    |> File.stream!()
    |> Stream.map(&parse_line/1)
    |> Stream.reject(&is_nil/1)
    |> build_occurrences()
  end

  defp parse_line(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, obj} -> obj
      _ -> nil
    end
  end

  defp build_occurrences(lines) do
    # Two-pass: collect tool_use entries, then match with tool_result
    {tool_uses, tool_results} =
      Enum.reduce(lines, {%{}, %{}}, fn obj, {uses, results} ->
        case obj do
          %{"type" => "assistant", "message" => msg} ->
            new_uses = extract_tool_uses(msg, obj)
            {Map.merge(uses, new_uses), results}

          %{"type" => "user", "message" => msg} ->
            new_results = extract_tool_results(msg)
            {uses, Map.merge(results, new_results)}

          _ ->
            {uses, results}
        end
      end)

    file_occs = build_file_read_occurrences(tool_uses)
    error_occs = build_error_occurrences(tool_uses, tool_results)

    file_occs ++ error_occs
  end

  defp extract_tool_uses(%{"content" => content}, obj) when is_list(content) do
    timestamp = Map.get(obj, "timestamp")

    content
    |> Enum.filter(fn c -> is_map(c) and c["type"] == "tool_use" end)
    |> Map.new(fn c ->
      {c["id"], %{name: c["name"], input: c["input"] || %{}, timestamp: timestamp}}
    end)
  end

  defp extract_tool_uses(_, _), do: %{}

  defp extract_tool_results(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(fn c -> is_map(c) and c["type"] == "tool_result" end)
    |> Map.new(fn c ->
      {c["tool_use_id"], %{is_error: c["is_error"] == true, content: c["content"]}}
    end)
  end

  defp extract_tool_results(_), do: %{}

  defp build_file_read_occurrences(tool_uses) do
    tool_uses
    |> Enum.filter(fn {_id, use} -> use.name in @file_tools end)
    |> Enum.map(fn {_id, use} -> extract_file_path(use.input) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_path/1)
    |> Enum.uniq()
    |> Enum.map(fn file ->
      Occurrence.new(
        "agent.file_read",
        %{file: file},
        Source.new("claude", "claude", ULID.generate())
      )
    end)
  end

  defp build_error_occurrences(tool_uses, tool_results) do
    tool_results
    |> Enum.filter(fn {_id, result} -> result.is_error end)
    |> Enum.map(fn {id, result} ->
      use = Map.get(tool_uses, id, %{name: "unknown", input: %{}})
      error_text = truncate(to_string(result.content), 200)

      Occurrence.new(
        "agent.tool_error",
        %{tool: use.name, error: error_text},
        Source.new("claude", "claude", ULID.generate())
      )
    end)
  end

  defp extract_file_path(%{"file_path" => path}) when is_binary(path), do: path
  defp extract_file_path(_), do: nil

  defp normalize_path(path) do
    cwd = File.cwd!()

    if String.starts_with?(path, cwd) do
      path |> String.replace_prefix(cwd <> "/", "") |> String.replace_prefix(cwd, "")
    else
      path
    end
  end

  defp truncate(str, max) when byte_size(str) > max, do: binary_part(str, 0, max) <> "..."
  defp truncate(str, _max), do: str

  defp ulid_to_ms(nil), do: nil

  defp ulid_to_ms(ulid) when is_binary(ulid) and byte_size(ulid) >= 10 do
    crockford = ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    ulid
    |> String.slice(0, 10)
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      idx = Enum.find_index(crockford, &(&1 == char)) || 0
      acc * 32 + idx
    end)
  end

  defp ulid_to_ms(_), do: nil
end
