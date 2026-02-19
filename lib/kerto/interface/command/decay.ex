defmodule Kerto.Interface.Command.Decay do
  @moduledoc """
  Forces a decay cycle on the knowledge graph.
  """

  alias Kerto.Interface.{Response, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    raw = Map.get(args, :factor, Kerto.Engine.Config.get(:decay_factor))

    case Validate.float_val(raw, "factor") do
      {:ok, factor} ->
        Kerto.Engine.decay(engine, factor)
        Response.success(:ok)

      {:error, reason} ->
        Response.error(reason)
    end
  end
end
