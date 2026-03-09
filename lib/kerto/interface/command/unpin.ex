defmodule Kerto.Interface.Command.Unpin do
  @moduledoc """
  Unpins a node or relationship, allowing normal decay and pruning.
  """

  alias Kerto.Interface.{Response, Suggest, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    node = Map.get(args, :node)
    source = Map.get(args, :source)
    relation = Map.get(args, :relation)
    target = Map.get(args, :target)

    cond do
      not is_nil(node) ->
        unpin_node(engine, node, args)

      not is_nil(source) and not is_nil(relation) and not is_nil(target) ->
        unpin_relationship(engine, source, relation, target, args)

      true ->
        Response.error("specify --node or --source/--relation/--target")
    end
  end

  defp unpin_node(engine, node, args) do
    case Validate.node_kind(Map.get(args, :kind, :file)) do
      {:ok, kind} ->
        case Kerto.Engine.unpin_node(engine, kind, node) do
          :ok -> Response.success(:ok)
          {:error, :not_found} -> Response.error(not_found_message(engine, kind, node))
        end

      {:error, reason} ->
        Response.error(reason)
    end
  end

  defp not_found_message(engine, kind, name) do
    case Suggest.similar_names(engine, kind, name) do
      [] -> "not found: #{name} (#{kind})"
      similar -> "not found: #{name} (#{kind}). Similar: #{Enum.join(similar, ", ")}"
    end
  end

  defp unpin_relationship(engine, source, relation, target, args) do
    with {:ok, source_kind} <- Validate.node_kind(Map.get(args, :source_kind, :file)),
         {:ok, target_kind} <- Validate.node_kind(Map.get(args, :target_kind, :file)),
         {:ok, relation_atom} <- Validate.relation(relation) do
      case Kerto.Engine.unpin_relationship(
             engine,
             source_kind,
             source,
             relation_atom,
             target_kind,
             target
           ) do
        :ok -> Response.success(:ok)
        {:error, :not_found} -> Response.error("relationship not found")
      end
    else
      {:error, reason} -> Response.error(reason)
    end
  end
end
