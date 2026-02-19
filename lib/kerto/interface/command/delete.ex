defmodule Kerto.Interface.Command.Delete do
  @moduledoc """
  Hard-removes a node or relationship from the graph.
  """

  alias Kerto.Interface.{Response, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    node = Map.get(args, :node)
    source = Map.get(args, :source)
    relation = Map.get(args, :relation)
    target = Map.get(args, :target)

    cond do
      not is_nil(node) ->
        delete_node(engine, node, args)

      not is_nil(source) and not is_nil(relation) and not is_nil(target) ->
        delete_relationship(engine, source, relation, target, args)

      true ->
        Response.error("specify --node or --source/--relation/--target")
    end
  end

  defp delete_node(engine, node, args) do
    case Validate.node_kind(Map.get(args, :kind, :file)) do
      {:ok, kind} ->
        case Kerto.Engine.delete_node(engine, kind, node) do
          :ok -> Response.success(:ok)
          {:error, :not_found} -> Response.error(:not_found)
        end

      {:error, reason} ->
        Response.error(reason)
    end
  end

  defp delete_relationship(engine, source, relation, target, args) do
    with {:ok, source_kind} <- Validate.node_kind(Map.get(args, :source_kind, :file)),
         {:ok, target_kind} <- Validate.node_kind(Map.get(args, :target_kind, :file)),
         {:ok, relation_atom} <- Validate.relation(relation) do
      case Kerto.Engine.delete_relationship(
             engine,
             source_kind,
             source,
             relation_atom,
             target_kind,
             target
           ) do
        :ok -> Response.success(:ok)
        {:error, :not_found} -> Response.error(:not_found)
      end
    else
      {:error, reason} -> Response.error(reason)
    end
  end
end
