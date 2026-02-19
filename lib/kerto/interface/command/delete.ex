defmodule Kerto.Interface.Command.Delete do
  @moduledoc """
  Hard-removes a node or relationship from the graph.
  """

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    cond do
      Map.has_key?(args, :node) ->
        delete_node(engine, args)

      Map.has_key?(args, :source) and Map.has_key?(args, :relation) and
          Map.has_key?(args, :target) ->
        delete_relationship(engine, args)

      true ->
        Response.error("specify --node or --source/--relation/--target")
    end
  end

  defp delete_node(engine, args) do
    kind = Map.get(args, :kind, :file)

    case Kerto.Engine.delete_node(engine, kind, args.node) do
      :ok -> Response.success(:ok)
      {:error, :not_found} -> Response.error(:not_found)
    end
  end

  defp delete_relationship(engine, args) do
    source_kind = Map.get(args, :source_kind, :file)
    target_kind = Map.get(args, :target_kind, :file)
    relation = to_atom(args.relation)

    case Kerto.Engine.delete_relationship(
           engine,
           source_kind,
           args.source,
           relation,
           target_kind,
           args.target
         ) do
      :ok -> Response.success(:ok)
      {:error, :not_found} -> Response.error(:not_found)
    end
  end

  defp to_atom(val) when is_atom(val), do: val
  defp to_atom(val) when is_binary(val), do: String.to_existing_atom(val)
end
