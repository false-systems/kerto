defmodule Kerto.Interface.Command.Bootstrap do
  @moduledoc """
  Cold-start bootstrap: seeds the knowledge graph from git history and file tree.

  Shells out to `git log` and `git ls-files`, then ingests the results
  as `bootstrap.git_history` and `bootstrap.file_tree` occurrences.
  Idempotent — skips if the graph already has more than 10 nodes.
  """

  alias Kerto.Interface.{Response, ULID}
  alias Kerto.Ingestion.{Occurrence, Source}

  @batch_size 20

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, _args) do
    if Kerto.Engine.node_count(engine) > 10 do
      Response.success("bootstrap skipped (graph already populated)")
    else
      case run_bootstrap(engine) do
        {:ok, stats} -> Response.success("bootstrap complete: #{stats}")
        {:error, reason} -> Response.error("bootstrap failed: #{reason}")
      end
    end
  end

  defp run_bootstrap(engine) do
    with {:ok, commits} <- parse_git_log(),
         {:ok, files} <- parse_git_ls_files() do
      commit_count = ingest_git_history(engine, commits)
      file_count = ingest_file_tree(engine, files)
      {:ok, "#{commit_count} commits, #{file_count} files"}
    end
  end

  defp parse_git_log do
    case System.cmd("git", ["log", "--pretty=format:%H %s", "--name-only", "-200"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, parse_commits(output)}
      {error, _} -> {:error, "git log failed: #{String.slice(error, 0, 100)}"}
    end
  end

  defp parse_commits(output) do
    output
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn block ->
      lines = String.split(block, "\n", trim: true)

      case lines do
        [header | file_lines] ->
          message =
            case String.split(header, " ", parts: 2) do
              [_hash, msg] -> msg
              _ -> ""
            end

          %{message: message, files: file_lines |> Enum.reject(&String.contains?(&1, " "))}

        _ ->
          %{message: "", files: []}
      end
    end)
    |> Enum.reject(fn c -> c.files == [] end)
  end

  defp parse_git_ls_files do
    case System.cmd("git", ["ls-files"], stderr_to_stdout: true) do
      {output, 0} ->
        files = output |> String.split("\n", trim: true)
        {:ok, files}

      {error, _} ->
        {:error, "git ls-files failed: #{String.slice(error, 0, 100)}"}
    end
  end

  defp ingest_git_history(engine, commits) do
    commits
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      source = Source.new("kerto", "bootstrap", ULID.generate())

      occ = Occurrence.new("bootstrap.git_history", %{commits: batch}, source)
      Kerto.Engine.ingest(engine, occ)
    end)

    length(commits)
  end

  defp ingest_file_tree(engine, files) do
    source = Source.new("kerto", "bootstrap", ULID.generate())
    occ = Occurrence.new("bootstrap.file_tree", %{files: files}, source)
    Kerto.Engine.ingest(engine, occ)
    length(files)
  end
end
