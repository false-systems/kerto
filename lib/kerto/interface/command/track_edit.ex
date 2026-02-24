defmodule Kerto.Interface.Command.TrackEdit do
  @moduledoc "Tracks a file edit in the session buffer."

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    file = Map.get(args, :file)
    session = Map.get(args, :session, "default")

    case file do
      nil ->
        Response.error("missing required argument: file")

      file when is_binary(file) and byte_size(file) > 0 ->
        Kerto.Engine.track_edit(engine, session, file)
        Response.success(:ok)

      _ ->
        Response.error("file must be a non-empty string")
    end
  end
end
