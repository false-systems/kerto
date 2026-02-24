defmodule Kerto.Ingestion.Extractor.GitHistory do
  @moduledoc """
  Extracts graph operations from `bootstrap.git_history` occurrences.

  Reuses the commit extractor pattern but at lower confidence (0.3),
  since historical data is weaker evidence than live observations.
  Each committed file becomes a `:file` node. File pairs get
  bidirectional `:often_changes_with` relationships.
  """

  alias Kerto.Ingestion.Occurrence

  @confidence 0.3

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "bootstrap.git_history", data: data}) do
    commits = Map.get(data, :commits, [])

    Enum.flat_map(commits, fn commit ->
      files =
        commit
        |> Map.get(:files, [])
        |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))

      message = Map.get(commit, :message, "")

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
             evidence: "git history: #{message}"
           }}
        end

      node_ops ++ rel_ops
    end)
  end
end
