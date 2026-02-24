defmodule Kerto.Ingestion.Extractor.SessionEdits do
  @moduledoc """
  Extracts graph operations from `agent.session_edits` occurrences.

  Creates file nodes at 0.6 confidence (higher than individual edits —
  session context means intent) and pairwise `:edited_with` relationships
  at 0.5 confidence. Only creates relationships when file count is 2-20
  to avoid N² explosion and single-file noise.
  """

  alias Kerto.Ingestion.Occurrence

  @file_confidence 0.6
  @rel_confidence 0.5
  @min_files 2
  @max_files 20

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.session_edits", data: data}) do
    files = data |> Map.get(:files, []) |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))
    agent = Map.get(data, :agent, "unknown")

    node_ops =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: @file_confidence}}
      end)

    rel_ops =
      if length(files) >= @min_files and length(files) <= @max_files do
        for a <- files, b <- files, a < b do
          {:upsert_relationship,
           %{
             source_kind: :file,
             source_name: a,
             relation: :edited_with,
             target_kind: :file,
             target_name: b,
             confidence: @rel_confidence,
             evidence: "co-edited in session by #{agent}"
           }}
        end
      else
        []
      end

    node_ops ++ rel_ops
  end
end
