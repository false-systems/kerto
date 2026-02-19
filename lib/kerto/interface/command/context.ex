defmodule Kerto.Interface.Command.Context do
  @moduledoc """
  Queries the knowledge graph for an entity and returns rendered context.
  """

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    name = Map.get(args, :name)

    if is_nil(name) do
      Response.error("missing required argument: name")
    else
      kind = Map.get(args, :kind, :file)
      opts = context_opts(args)

      case Kerto.Engine.context(engine, kind, name, opts) do
        {:ok, text} -> Response.success(text)
        {:error, :not_found} -> Response.error(:not_found)
      end
    end
  end

  defp context_opts(args) do
    []
    |> maybe_add(:depth, args)
    |> maybe_add(:min_weight, args)
  end

  defp maybe_add(opts, key, args) do
    case Map.get(args, key) do
      nil -> opts
      val -> Keyword.put(opts, key, val)
    end
  end
end
