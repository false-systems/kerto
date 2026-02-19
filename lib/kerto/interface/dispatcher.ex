defmodule Kerto.Interface.Dispatcher do
  @moduledoc """
  Routes command names to their implementing modules.
  """

  alias Kerto.Interface.Command
  alias Kerto.Interface.Response

  @command_map %{
    "status" => Command.Status,
    "context" => Command.Context,
    "learn" => Command.Learn,
    "decide" => Command.Decide,
    "ingest" => Command.Ingest,
    "graph" => Command.Graph,
    "decay" => Command.Decay,
    "weaken" => Command.Weaken,
    "delete" => Command.Delete
  }

  @spec dispatch(String.t(), atom(), map()) :: Response.t()
  def dispatch(command_name, engine, args) do
    case Map.get(@command_map, command_name) do
      nil -> Response.error("unknown command: #{command_name}")
      module -> module.execute(engine, args)
    end
  end

  @spec commands() :: [String.t()]
  def commands, do: Map.keys(@command_map)
end
