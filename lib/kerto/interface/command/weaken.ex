defmodule Kerto.Interface.Command.Weaken do
  @moduledoc """
  Applies counter-evidence to a relationship, reducing its weight.
  """

  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, source} <- require_arg(args, :source),
         {:ok, relation} <- require_arg(args, :relation),
         {:ok, target} <- require_arg(args, :target) do
      source_kind = Map.get(args, :source_kind, :file)
      target_kind = Map.get(args, :target_kind, :file)
      factor = Map.get(args, :factor, 0.5)

      ops = [
        {:weaken_relationship,
         %{
           source_kind: source_kind,
           source_name: source,
           relation: to_atom(relation),
           target_kind: target_kind,
           target_name: target,
           factor: factor
         }}
      ]

      Kerto.Engine.Store.apply_ops(child_store(engine), ops, ULID.generate())
      Response.success(:ok)
    end
  end

  defp child_store(engine), do: :"#{engine}.store"

  defp to_atom(val) when is_atom(val), do: val
  defp to_atom(val) when is_binary(val), do: String.to_existing_atom(val)

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
