defmodule Kerto.Interface.Command.Graph do
  @moduledoc """
  Dumps the full knowledge graph in JSON or DOT format.
  """

  alias Kerto.Graph.Graph
  alias Kerto.Interface.{Response, Serialize}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    graph = Kerto.Engine.get_graph(engine)
    format = Map.get(args, :format, :json)

    case format do
      :json -> Response.success(to_json(graph))
      :dot -> Response.success(to_dot(graph))
      other -> Response.error("unknown format: #{other}")
    end
  end

  defp to_json(%Graph{} = graph) do
    nodes =
      graph.nodes
      |> Map.values()
      |> Enum.map(&Serialize.node_to_map/1)

    relationships =
      graph.relationships
      |> Map.values()
      |> Enum.map(&Serialize.rel_to_map(&1, graph.nodes))

    %{nodes: nodes, relationships: relationships}
  end

  defp to_dot(%Graph{} = graph) do
    edges =
      graph.relationships
      |> Map.values()
      |> Enum.map_join("\n", fn rel ->
        source_name = resolve_name(graph, rel.source)
        target_name = resolve_name(graph, rel.target)
        weight = :erlang.float_to_binary(rel.weight, decimals: 2)
        "  \"#{source_name}\" -> \"#{target_name}\" [label=\"#{rel.relation} (#{weight})\"];"
      end)

    "digraph kerto {\n" <> edges <> "\n}"
  end

  defp resolve_name(graph, id) do
    case Map.get(graph.nodes, id) do
      nil -> id
      node -> node.name
    end
  end
end
