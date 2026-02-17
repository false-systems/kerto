defmodule Kerto.Ingestion.Extractor.Learning do
  @moduledoc """
  Extracts graph operations from `context.learning` occurrences.

  Creates subject and target nodes with the specified relationship.
  Captures knowledge like "auth.go OOM was caused by unbounded cache".
  Default confidence 0.8 — human-provided context is high-trust.
  """

  alias Kerto.Ingestion.Occurrence

  @default_confidence 0.8

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "context.learning", data: data}) do
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
         relation: data.relation,
         target_kind: data.target_kind,
         target_name: data.target_name,
         confidence: confidence,
         evidence: data.evidence
       }}

    [subject_node, target_node, relationship]
  end
end
