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

  @spec path(String.t()) :: String.t()
  def path(base_dir), do: Path.join(base_dir, "graph.etf")

  defp safe_decode(binary) do
    case safe_binary_to_term(binary) do
      %Graph{} = graph -> graph
      _ -> Graph.new()
    end
  end

  defp safe_binary_to_term(binary) do
    :erlang.binary_to_term(binary, [:safe])
  rescue
    ArgumentError -> nil
  end
end
