defmodule Kerto.Interface.Response do
  @moduledoc """
  Standardized response for all commands.

  Every command returns `Response.t()` — transports (CLI, MCP, socket)
  format it for their medium. Commands never do IO directly.
  """

  @enforce_keys [:ok]
  defstruct [:ok, :data, :error]

  @type t :: %__MODULE__{
          ok: boolean(),
          data: term(),
          error: term()
        }

  @spec success(term()) :: t()
  def success(data), do: %__MODULE__{ok: true, data: data}

  @spec error(term()) :: t()
  def error(reason), do: %__MODULE__{ok: false, error: reason}
end
