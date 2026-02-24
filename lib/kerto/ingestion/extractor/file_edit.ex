defmodule Kerto.Ingestion.Extractor.FileEdit do
  @moduledoc """
  Extracts graph operations from `agent.file_edit` occurrences.

  Each edited file becomes a `:file` node at confidence 0.4 — a single
  edit is weak evidence of importance. EWMA across sessions builds weight.
  No relationships — single edits lack semantic context.
  """

  alias Kerto.Ingestion.Occurrence

  @confidence 0.4

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.file_edit", data: data}) do
    file = Map.get(data, :file, "")
    [{:upsert_node, %{kind: :file, name: file, confidence: @confidence}}]
  end
end
