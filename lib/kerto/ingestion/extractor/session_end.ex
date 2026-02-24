defmodule Kerto.Ingestion.Extractor.SessionEnd do
  @moduledoc """
  Extracts graph operations from `agent.session_end` occurrences.

  Creates a concept node from the slugified summary, file nodes for each
  mentioned file, and `:learned` relationships from files to the concept.
  Files get confidence 0.7 (central to session), concept and relationships
  get 0.6.
  """

  alias Kerto.Ingestion.Occurrence

  @file_confidence 0.7
  @concept_confidence 0.6

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.session_end", data: data}) do
    summary = Map.get(data, :summary, "")
    files = data |> Map.get(:files, []) |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))
    slug = slugify(summary)

    concept_node = {:upsert_node, %{kind: :concept, name: slug, confidence: @concept_confidence}}

    file_nodes =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: @file_confidence}}
      end)

    relationships =
      Enum.map(files, fn file ->
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: file,
           relation: :learned,
           target_kind: :concept,
           target_name: slug,
           confidence: @concept_confidence,
           evidence: summary
         }}
      end)

    [concept_node] ++ file_nodes ++ relationships
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> String.slice(0, 60)
  end
end
