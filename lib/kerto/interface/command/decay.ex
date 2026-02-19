defmodule Kerto.Interface.Command.Decay do
  @moduledoc """
  Forces a decay cycle on the knowledge graph.
  """

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    factor = Map.get(args, :factor, Kerto.Engine.Config.get(:decay_factor))
    Kerto.Engine.decay(engine, factor)
    Response.success(:ok)
  end
end
