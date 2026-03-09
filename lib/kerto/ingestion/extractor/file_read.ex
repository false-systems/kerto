defmodule Kerto.Ingestion.Extractor.FileRead do
  @moduledoc """
  Extracts graph operations from `agent.file_read` occurrences.

  Creates a single `:file` node at low confidence (0.1) — reading a file
  is weak evidence of importance. No relationships created; the signal
  is purely "this file was looked at."
  """

  alias Kerto.Ingestion.Occurrence

  @confidence 0.1

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.file_read", data: data}) do
    case Map.get(data, :file) do
      file when is_binary(file) and byte_size(file) > 0 ->
        [{:upsert_node, %{kind: :file, name: file, confidence: @confidence}}]

      _ ->
        []
    end
  end
end
