defmodule Kerto.Ingestion.Extractor.CiSuccess do
  @moduledoc """
  Extracts graph operations from `ci.run.passed` occurrences.

  Passing CI is counter-evidence for `:breaks` relationships.
  Creates weak file observations (0.1) and weakens existing
  `:breaks` edges by factor 0.5 (halves the weight).
  """

  alias Kerto.Ingestion.Occurrence

  @file_confidence 0.1
  @task_confidence 0.1
  @weaken_factor 0.5

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "ci.run.passed", data: data}) do
    files = Map.get(data, :files, [])
    task = Map.fetch!(data, :task)

    case files do
      [] ->
        []

      files ->
        file_nodes =
          Enum.map(files, fn file ->
            {:upsert_node, %{kind: :file, name: file, confidence: @file_confidence}}
          end)

        task_node = {:upsert_node, %{kind: :module, name: task, confidence: @task_confidence}}

        weakens =
          Enum.map(files, fn file ->
            {:weaken_relationship,
             %{
               source_kind: :file,
               source_name: file,
               relation: :breaks,
               target_kind: :module,
               target_name: task,
               factor: @weaken_factor
             }}
          end)

        file_nodes ++ [task_node] ++ weakens
    end
  end
end
