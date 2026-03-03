defmodule Kerto.Interface.Command.Bootstrap do
  @moduledoc "Seeds the knowledge graph from git history and file tree."

  alias Kerto.Engine.Persistence
  alias Kerto.Interface.{Response, ULID}
  alias Kerto.Ingestion.{Occurrence, Source}

  @batch_size 20

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, _args) do
    persistence_path = Kerto.Engine.persistence_path(engine)
    current_fp = git_root_commit()
    stored_fp = if persistence_path, do: Persistence.load_fingerprint(persistence_path)

    cond do
      stored_fp != nil and current_fp != nil and stored_fp != current_fp ->
        Kerto.Engine.clear(engine)
        do_bootstrap(engine, persistence_path, current_fp, "re-bootstrap (repo changed)")

      Kerto.Engine.node_count(engine) > 10 ->
        maybe_save_fingerprint(persistence_path, current_fp)
        Response.success("bootstrap skipped (graph already populated)")

      true ->
        do_bootstrap(engine, persistence_path, current_fp, "bootstrap complete")
    end
  end

  defp do_bootstrap(engine, persistence_path, fingerprint, prefix) do
    case run_bootstrap(engine) do
      {:ok, stats} ->
        maybe_save_fingerprint(persistence_path, fingerprint)
        Response.success("#{prefix}: #{stats}")

      {:error, reason} ->
        Response.error("bootstrap failed: #{reason}")
    end
  end

  defp maybe_save_fingerprint(nil, _fingerprint), do: :ok
  defp maybe_save_fingerprint(_path, nil), do: :ok

  defp maybe_save_fingerprint(path, fingerprint),
    do: Persistence.save_fingerprint(path, fingerprint)

  defp git_root_commit do
    case System.cmd("git", ["rev-list", "--max-parents=0", "HEAD"], stderr_to_stdout: true) do
      {output, 0} -> output |> String.trim() |> String.split("\n") |> List.first()
      _ -> nil
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

          %{message: message, files: file_lines |> Enum.reject(&String.starts_with?(&1, "%H "))}

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
