defmodule Kerto.Ingestion.Extractor.Commit do
  @moduledoc """
  Extracts graph operations from `vcs.commit` occurrences.

  Each committed file becomes a `:file` node. File pairs get
  bidirectional `:often_changes_with` relationships. Confidence 0.5 —
  a single co-change is weak evidence of structural coupling.
  """

  alias Kerto.Ingestion.Occurrence

  @confidence 0.5

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "vcs.commit", data: data}) do
    files = Map.get(data, :files, [])
    message = Map.get(data, :message, "")

    node_ops =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: @confidence}}
      end)

    rel_ops =
      for a <- files, b <- files, a != b do
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: a,
           relation: :often_changes_with,
           target_kind: :file,
           target_name: b,
           confidence: @confidence,
           evidence: "commit: #{message}"
         }}
      end

    node_ops ++ rel_ops
  end
end
