defmodule Kerto.Ingestion.Extractor.ApproachAbandoned do
  @moduledoc """
  Extracts graph operations from `agent.approach_abandoned` occurrences.

  When an agent tries an approach and abandons it, this creates a
  `:tried_failed` relationship between the subject and the approach.
  This is negative knowledge — "we tried X for Y and it didn't work."

  Expected data:
    - subject: the entity the approach was tried on (e.g. "auth.go")
    - subject_kind: kind of subject (default: :file)
    - approach: what was tried (e.g. "redis caching")
    - approach_kind: kind of approach (default: :pattern)
    - reason: why it was abandoned (optional, becomes evidence)
  """

  alias Kerto.Graph.EWMA
  alias Kerto.Ingestion.Occurrence

  @default_confidence 0.7

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.approach_abandoned", data: data}) do
    subject = Map.get(data, :subject)
    approach = Map.get(data, :approach)

    if is_binary(subject) and byte_size(subject) > 0 and
         is_binary(approach) and byte_size(approach) > 0 do
      subject_kind = Map.get(data, :subject_kind, :file)
      approach_kind = Map.get(data, :approach_kind, :pattern)
      reason = Map.get(data, :reason, "approach abandoned")
      confidence = data |> Map.get(:confidence, @default_confidence) |> EWMA.clamp()

      subject_node =
        {:upsert_node, %{kind: subject_kind, name: subject, confidence: confidence}}

      approach_node =
        {:upsert_node, %{kind: approach_kind, name: approach, confidence: confidence}}

      relationship =
        {:upsert_relationship,
         %{
           source_kind: subject_kind,
           source_name: subject,
           relation: :tried_failed,
           target_kind: approach_kind,
           target_name: approach,
           confidence: confidence,
           evidence: reason
         }}

      [subject_node, approach_node, relationship]
    else
      []
    end
  end
end
