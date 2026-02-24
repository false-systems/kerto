defmodule Kerto.Ingestion.Extractor.ToolError do
  @moduledoc """
  Extracts graph operations from `agent.tool_error` occurrences.

  Creates an `:error` kind node from the error text (slugified, max 60 chars).
  If files provided, creates `:caused_by` relationships from file nodes to error node.
  """

  alias Kerto.Graph.EWMA
  alias Kerto.Ingestion.Occurrence

  @node_confidence 0.6
  @rel_confidence 0.5
  @max_slug_length 60

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "agent.tool_error", data: data}) do
    error = Map.get(data, :error, "")
    tool = Map.get(data, :tool, "unknown")
    files = data |> Map.get(:files, []) |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))

    error_slug = slugify(error, @max_slug_length)

    node_confidence = data |> Map.get(:confidence, @node_confidence) |> EWMA.clamp()
    rel_confidence = data |> Map.get(:rel_confidence, @rel_confidence) |> EWMA.clamp()

    error_node = [{:upsert_node, %{kind: :error, name: error_slug, confidence: node_confidence}}]

    file_nodes =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: rel_confidence}}
      end)

    relationships =
      Enum.map(files, fn file ->
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: file,
           relation: :caused_by,
           target_kind: :error,
           target_name: error_slug,
           confidence: rel_confidence,
           evidence: "Tool error (#{tool}): #{String.slice(error, 0, 120)}"
         }}
      end)

    error_node ++ file_nodes ++ relationships
  end

  defp slugify(text, max_length) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> String.slice(0, max_length)
  end
end
