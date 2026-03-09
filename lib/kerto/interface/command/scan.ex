defmodule Kerto.Interface.Command.Scan do
  @moduledoc """
  Manually triggers a plugin scan cycle.
  """

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, _args) do
    Kerto.Engine.scan_plugins(engine)
    Response.success("scan complete")
  end
end
