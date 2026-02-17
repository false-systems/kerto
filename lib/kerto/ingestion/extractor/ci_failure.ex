defmodule Kerto.Ingestion.Extractor.CiFailure do
  @moduledoc """
  Extracts graph operations from `ci.run.failed` occurrences.

  Creates file nodes + a module node for the failed task, then
  `:breaks` relationships from each file to the task. Confidence
  defaults to 0.7 (CI failures are strong but not certain evidence).
  """

  alias Kerto.Ingestion.Occurrence

  @default_confidence 0.7

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "ci.run.failed", data: data}) do
    files = Map.get(data, :files, [])
    task = Map.fetch!(data, :task)
    confidence = Map.get(data, :confidence, @default_confidence)
    error = Map.get(data, :error, "")

    evidence =
      case error do
        "" -> "CI failure: #{task} failed"
        err -> "CI failure: #{task} failed — #{err}"
      end

    file_nodes =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: confidence}}
      end)

    task_node = {:upsert_node, %{kind: :module, name: task, confidence: confidence}}

    breaks =
      Enum.map(files, fn file ->
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: file,
           relation: :breaks,
           target_kind: :module,
           target_name: task,
           confidence: confidence,
           evidence: evidence
         }}
      end)

    file_nodes ++ [task_node] ++ breaks
  end
end
