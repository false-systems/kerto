defmodule Kerto.Ingestion.Occurrence do
  @moduledoc """
  Immutable input from external sources — the raw material of knowledge.

  An occurrence is a typed event with arbitrary data and a provenance source.
  Extractors pattern-match on `type` to produce graph operations.
  """

  alias Kerto.Ingestion.Source

  @enforce_keys [:type, :data, :source]
  defstruct [:type, :data, :source]

  @type t :: %__MODULE__{
          type: String.t(),
          data: map(),
          source: Source.t()
        }

  @spec new(String.t(), map(), Source.t()) :: t()
  def new(type, data, %Source{} = source)
      when is_binary(type) and is_map(data) do
    %__MODULE__{type: type, data: data, source: source}
  end
end
