defmodule Kerto.Rendering.Query do
  @moduledoc """
  Coordinates graph queries into rendering Contexts.

  Given a kind and name, finds the focal node via content-addressed
  identity, extracts its local subgraph, and builds a Context ready
  for the Renderer.
  """

  alias Kerto.Graph.{Graph, Identity}
  alias Kerto.Rendering.Context

  @spec query_context(Graph.t(), atom(), String.t(), String.t(), keyword()) ::
          {:ok, Context.t()} | {:error, :not_found}
  def query_context(%Graph{} = graph, kind, name, _now, opts \\ []) do
    id = Identity.compute_id(kind, name)

    case Graph.get_node(graph, id) do
      :error ->
        {:error, :not_found}

      {:ok, node} ->
        depth = Keyword.get(opts, :depth, 2)
        min_weight = Keyword.get(opts, :min_weight, 0.0)

        {nodes, rels} = Graph.subgraph(graph, id, depth: depth, min_weight: min_weight)

        node_lookup =
          nodes
          |> Enum.map(&{&1.id, &1})
          |> Map.new()

        {:ok, Context.new(node, rels, node_lookup)}
    end
  end
end
