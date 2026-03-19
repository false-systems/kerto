defmodule Kerto.Interface.Command.Grep do
  @moduledoc """
  Searches nodes or relationships by name/evidence substring.
  """

  alias Kerto.Interface.{Response, Serialize, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    case Map.get(args, :pattern) do
      nil ->
        Response.error("missing required argument: pattern")

      pattern ->
        if search_relationships?(args) do
          search_rels(engine, pattern, args)
        else
          search_nodes(engine, pattern, args)
        end
    end
  end

  defp search_relationships?(args) do
    Map.get(args, :evidence, false) == true or
      Map.get(args, :type) in ["rels", "relationships", "rel"]
  end

  defp search_nodes(engine, pattern, args) do
    opts =
      case Map.get(args, :kind) do
        nil ->
          []

        kind ->
          case Validate.node_kind(kind) do
            {:ok, k} -> [kind: k]
            {:error, reason} -> {:error, reason}
          end
      end

    case opts do
      {:error, reason} ->
        Response.error(reason)

      opts ->
        nodes = Kerto.Engine.search_nodes(engine, pattern, opts)
        Response.success(%{nodes: Enum.map(nodes, &Serialize.node_to_map/1)})
    end
  end

  defp search_rels(engine, pattern, args) do
    opts =
      case Map.get(args, :relation) do
        nil ->
          []

        rel ->
          case Validate.relation(rel) do
            {:ok, r} -> [relation: r]
            {:error, reason} -> {:error, reason}
          end
      end

    case opts do
      {:error, reason} ->
        Response.error(reason)

      opts ->
        graph = Kerto.Engine.get_graph(engine)
        rels = Kerto.Graph.Graph.search_relationships(graph, pattern, opts)
        lookup = graph.nodes
        Response.success(%{relationships: Enum.map(rels, &Serialize.rel_to_map(&1, lookup))})
    end
  end
end
