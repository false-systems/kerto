defmodule Kerto.Interface.Command.List do
  @moduledoc """
  Lists nodes or relationships with optional filters.
  """

  alias Kerto.Interface.{Response, Validate}

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
        Response.success(format_nodes(nodes))
    end
  end

  defp list_relationships(engine, args) do
    opts = build_rel_opts(args)

    case opts do
      {:error, reason} ->
        Response.error(reason)

      opts ->
        rels = Kerto.Engine.list_relationships(engine, opts)
        Response.success(format_relationships(rels))
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

  defp format_nodes([]), do: "No nodes found."

  defp format_nodes(nodes) do
    header = "#{length(nodes)} node(s):\n"

    rows =
      Enum.map_join(nodes, "\n", fn node ->
        pin = if node.pinned, do: " [pinned]", else: ""

        "  #{node.kind}:#{node.name}  relevance=#{Float.round(node.relevance, 3)}  obs=#{node.observations}#{pin}"
      end)

    header <> rows
  end

  defp format_relationships([]), do: "No relationships found."

  defp format_relationships(rels) do
    header = "#{length(rels)} relationship(s):\n"

    rows =
      Enum.map_join(rels, "\n", fn rel ->
        pin = if rel.pinned, do: " [pinned]", else: ""

        "  #{short_id(rel.source)} --#{rel.relation}--> #{short_id(rel.target)}  weight=#{Float.round(rel.weight, 3)}  obs=#{rel.observations}#{pin}"
      end)

    header <> rows
  end

  defp short_id(id) when byte_size(id) > 8, do: String.slice(id, 0, 8) <> ".."
  defp short_id(id), do: id
end
