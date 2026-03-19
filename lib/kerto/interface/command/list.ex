defmodule Kerto.Interface.Command.List do
  @moduledoc """
  Lists nodes or relationships with optional filters.
  """

  alias Kerto.Interface.{Response, Serialize, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    case Map.get(args, :type, "nodes") do
      type when type in ["nodes", "node"] -> list_nodes(engine, args)
      type when type in ["relationships", "rels", "rel"] -> list_relationships(engine, args)
      other -> Response.error("unknown list type: #{other}. Use 'nodes' or 'relationships'")
    end
  end

  defp list_nodes(engine, args) do
    opts = build_node_opts(args)

    case opts do
      {:error, reason} ->
        Response.error(reason)

      opts ->
        nodes = Kerto.Engine.list_nodes(engine, opts)
        Response.success(%{nodes: Enum.map(nodes, &Serialize.node_to_map/1)})
    end
  end

  defp list_relationships(engine, args) do
    opts = build_rel_opts(args)

    case opts do
      {:error, reason} ->
        Response.error(reason)

      opts ->
        rels = Kerto.Engine.list_relationships(engine, opts)
        graph = Kerto.Engine.get_graph(engine)
        Response.success(%{relationships: Enum.map(rels, &Serialize.rel_to_map(&1, graph.nodes))})
    end
  end

  defp build_node_opts(args) do
    opts = []

    opts =
      case Map.get(args, :kind) do
        nil ->
          opts

        kind ->
          case Validate.node_kind(kind) do
            {:ok, k} -> [{:kind, k} | opts]
            {:error, reason} -> {:error, reason}
          end
      end

    case opts do
      {:error, _} = err ->
        err

      opts ->
        opts = if Map.get(args, :pinned), do: [{:pinned, true} | opts], else: opts

        opts =
          case Map.get(args, :below) do
            nil -> opts
            val when is_float(val) -> [{:below, val} | opts]
            val when is_integer(val) -> [{:below, val * 1.0} | opts]
            _ -> opts
          end

        opts
    end
  end

  defp build_rel_opts(args) do
    opts = []

    opts =
      case Map.get(args, :relation) do
        nil ->
          opts

        rel ->
          case Validate.relation(rel) do
            {:ok, r} -> [{:relation, r} | opts]
            {:error, reason} -> {:error, reason}
          end
      end

    case opts do
      {:error, _} = err ->
        err

      opts ->
        opts = if Map.get(args, :pinned), do: [{:pinned, true} | opts], else: opts

        opts =
          case Map.get(args, :below) do
            nil -> opts
            val when is_float(val) -> [{:below, val} | opts]
            val when is_integer(val) -> [{:below, val * 1.0} | opts]
            _ -> opts
          end

        opts
    end
  end
end
