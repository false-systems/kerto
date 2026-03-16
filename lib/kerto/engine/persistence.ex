defmodule Kerto.Engine.Persistence do
  @moduledoc """
  Save/load graph as ETF binary.
  """

  alias Kerto.Graph.Graph

  @spec save(Graph.t(), String.t()) :: :ok | {:error, term()}
  def save(%Graph{} = graph, path) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, :erlang.term_to_binary(graph)) do
      :ok
    else
      {:error, reason} ->
        require Logger
        Logger.warning("Persistence failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec load(String.t()) :: Graph.t()
  def load(path) do
    case File.read(path) do
      {:ok, binary} -> safe_decode(binary)
      {:error, _} -> Graph.new()
    end
  end

  @spec save_fingerprint(String.t(), String.t()) :: :ok | {:error, term()}
  def save_fingerprint(base_dir, fingerprint) when is_binary(fingerprint) do
    with :ok <- File.mkdir_p(base_dir),
         :ok <- File.write(fingerprint_path(base_dir), fingerprint) do
      :ok
    else
      {:error, reason} ->
        require Logger

        Logger.warning(
          "Persistence failed for fingerprint #{fingerprint_path(base_dir)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec load_fingerprint(String.t()) :: String.t() | nil
  def load_fingerprint(base_dir) do
    case File.read(fingerprint_path(base_dir)) do
      {:ok, data} -> String.trim(data)
      {:error, _} -> nil
    end
  end

  @spec path(String.t()) :: String.t()
  def path(base_dir), do: Path.join(base_dir, "graph.etf")

  @spec fingerprint_path(String.t()) :: String.t()
  def fingerprint_path(base_dir), do: Path.join(base_dir, "repo_fingerprint")

  defp safe_decode(binary) do
    case safe_binary_to_term(binary) do
      %Graph{} = graph -> graph
      _ -> Graph.new()
    end
  end

  # Trust boundary: :safe is intentionally omitted because the graph contains
  # module atoms (Kerto.Graph.*) created at compile time. Using :safe would
  # reject any ETF referencing these atoms if they weren't already in the
  # atom table (e.g. after a code change). The file is local, written only
  # by our own save/2 — external/network ETF must never reach this path.
  defp safe_binary_to_term(binary) do
    :erlang.binary_to_term(binary)
  rescue
    ArgumentError ->
      require Logger
      Logger.warning("Persistence: corrupt or incompatible data, returning empty graph")
      nil
  end
end
