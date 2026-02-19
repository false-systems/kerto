defmodule Kerto.Interface.Command.Weaken do
  @moduledoc """
  Applies counter-evidence to a relationship, reducing its weight.
  """

  alias Kerto.Interface.{Response, ULID, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, source} <- require_arg(args, :source),
         {:ok, relation} <- require_arg(args, :relation),
         {:ok, target} <- require_arg(args, :target),
         {:ok, source_kind} <- Validate.node_kind(Map.get(args, :source_kind, :file)),
         {:ok, target_kind} <- Validate.node_kind(Map.get(args, :target_kind, :file)),
         {:ok, relation_atom} <- Validate.relation(relation),
         {:ok, factor} <- Validate.float_val(Map.get(args, :factor, 0.5), "factor") do
      ops = [
        {:weaken_relationship,
         %{
           source_kind: source_kind,
           source_name: source,
           relation: relation_atom,
           target_kind: target_kind,
           target_name: target,
           factor: factor
         }}
      ]

      Kerto.Engine.Store.apply_ops(child_store(engine), ops, ULID.generate())
      Response.success(:ok)
    else
      %Response{ok: false} = resp -> resp
      {:error, reason} -> Response.error(reason)
    end
  end

  defp child_store(engine), do: :"#{engine}.store"

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
