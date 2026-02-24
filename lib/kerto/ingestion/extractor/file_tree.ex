defmodule Kerto.Ingestion.Extractor.FileTree do
  @moduledoc """
  Extracts graph operations from `bootstrap.file_tree` occurrences.

  Each file becomes a `:file` node at 0.2 confidence (structural,
  weakest signal). Files get `:part_of` relationships to their
  parent directory, modeled as a `:module` node.
  """

  alias Kerto.Ingestion.Occurrence

  @confidence 0.2

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "bootstrap.file_tree", data: data}) do
    files = data |> Map.get(:files, []) |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))

    node_ops =
      Enum.map(files, fn file ->
        {:upsert_node, %{kind: :file, name: file, confidence: @confidence}}
      end)

    dir_pairs =
      files
      |> Enum.map(fn file -> {file, Path.dirname(file)} end)
      |> Enum.reject(fn {_file, dir} -> dir == "." end)

    dir_node_ops =
      dir_pairs
      |> Enum.map(fn {_file, dir} -> dir end)
      |> Enum.uniq()
      |> Enum.map(fn dir ->
        {:upsert_node, %{kind: :module, name: dir, confidence: @confidence}}
      end)

    rel_ops =
      Enum.map(dir_pairs, fn {file, dir} ->
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: file,
           relation: :part_of,
           target_kind: :module,
           target_name: dir,
           confidence: @confidence,
           evidence: "file tree"
         }}
      end)

    node_ops ++ dir_node_ops ++ rel_ops
  end
end
