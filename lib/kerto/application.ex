defmodule Kerto.Application do
  @moduledoc """
  OTP Application supervisor.

  Starts the Engine under supervision with the default `:kerto_engine` name.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Kerto.Engine, name: :kerto_engine}
    ]

    opts = [strategy: :one_for_one, name: Kerto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
