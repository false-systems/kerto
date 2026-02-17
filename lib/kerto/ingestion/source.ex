defmodule Kerto.Ingestion.Source do
  @moduledoc """
  Value object identifying where an occurrence came from.

  Every piece of ingested knowledge carries provenance: which system
  produced it, which agent reported it, and when (ULID).
  """

  @enforce_keys [:system, :agent, :ulid]
  defstruct [:system, :agent, :ulid]

  @type t :: %__MODULE__{
          system: String.t(),
          agent: String.t(),
          ulid: String.t()
        }

  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(system, agent, ulid)
      when is_binary(system) and is_binary(agent) and is_binary(ulid) do
    %__MODULE__{system: system, agent: agent, ulid: ulid}
  end
end
