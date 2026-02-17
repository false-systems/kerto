defmodule Kerto.Ingestion.Extractor.Decision do
  @moduledoc """
  Extracts graph operations from `context.decision` occurrences.

  Creates subject and target nodes with a `:decided` relationship.
  Captures architectural decisions like "Use JWT over sessions".
  Default confidence 0.9 — decisions carry high weight.
  """

  alias Kerto.Ingestion.Occurrence

  @default_confidence 0.9

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "context.decision", data: data}) do
    confidence = Map.get(data, :confidence, @default_confidence)

    subject_node =
      {:upsert_node, %{kind: data.subject_kind, name: data.subject_name, confidence: confidence}}

    target_node =
      {:upsert_node, %{kind: data.target_kind, name: data.target_name, confidence: confidence}}

    relationship =
      {:upsert_relationship,
       %{
         source_kind: data.subject_kind,
         source_name: data.subject_name,
         relation: :decided,
         target_kind: data.target_kind,
         target_name: data.target_name,
         confidence: confidence,
         evidence: data.evidence
       }}

    [subject_node, target_node, relationship]
  end
end
