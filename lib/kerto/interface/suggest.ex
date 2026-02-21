defmodule Kerto.Interface.Suggest do
  @moduledoc """
  Fuzzy name matching for "did you mean?" hints.
  """

  @threshold 0.7

  @spec similar_names(atom(), atom(), String.t(), pos_integer()) :: [String.t()]
  def similar_names(engine, kind, query, limit \\ 3) do
    engine
    |> Kerto.Engine.list_nodes(kind: kind)
    |> Enum.map(fn node -> {node.name, String.jaro_distance(query, node.name)} end)
    |> Enum.filter(fn {_name, score} -> score >= @threshold end)
    |> Enum.sort_by(fn {_name, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {name, _score} -> name end)
  end
end
