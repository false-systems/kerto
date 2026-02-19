defmodule Kerto.Interface.Command.Status do
  @moduledoc """
  Returns graph statistics: node count, relationship count, occurrence count.
  """

  alias Kerto.Interface.Response

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, _args) do
    Response.success(Kerto.Engine.status(engine))
  end
end
