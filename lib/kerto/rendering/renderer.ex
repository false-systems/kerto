defmodule Kerto.Rendering.Renderer do
  @moduledoc """
  Transforms a rendering Context into natural language for agents.

  Sections: Caution (breaks/caused_by/triggers), Knowledge
  (learned/decided/tried_failed), Structure (depends_on/part_of/
  often_changes_with). Empty sections omitted. Sorted by weight desc.
  Max 3 evidence items per relationship.
  """

  alias Kerto.Rendering.Context

  @caution_relations [:breaks, :caused_by, :triggers]
  @knowledge_relations [:learned, :decided, :tried_failed]
  @structure_relations [:depends_on, :part_of, :often_changes_with]
  @max_evidence 3

  @spec render(Context.t()) :: String.t()
  def render(%Context{} = ctx) do
    header = render_header(ctx.node)

    sections =
      [
        render_section("Caution", ctx, @caution_relations),
        render_section("Knowledge", ctx, @knowledge_relations),
        render_section("Structure", ctx, @structure_relations)
      ]
      |> Enum.reject(&is_nil/1)

    [header | sections]
    |> Enum.join("\n\n")
  end

  defp render_header(node) do
    "#{node.name} (#{node.kind}) — relevance #{format_float(node.relevance)}, observed #{node.observations} times"
  end

  defp render_section(title, ctx, relations) do
    rels =
      ctx.relationships
      |> Enum.filter(&(&1.relation in relations))
      |> Enum.sort_by(& &1.weight, :desc)

    case rels do
      [] -> nil
      rels -> "#{title}:\n" <> Enum.map_join(rels, "\n", &render_relationship(&1, ctx))
    end
  end

  defp render_relationship(rel, ctx) do
    other_id = other_node_id(rel, ctx.node.id)
    other_name = resolve_name(other_id, ctx.node_lookup)

    header =
      "  #{rel.relation} #{other_name} (weight #{format_float(rel.weight)}, #{rel.observations} observations)"

    evidence_lines =
      rel.evidence
      |> Enum.take(@max_evidence)
      |> Enum.map_join("\n", fn ev -> "    \"#{ev}\"" end)

    header <> "\n" <> evidence_lines
  end

  defp other_node_id(rel, focal_id) do
    if rel.source == focal_id, do: rel.target, else: rel.source
  end

  defp resolve_name(id, lookup) do
    case Map.get(lookup, id) do
      nil -> id
      node -> node.name
    end
  end

  defp format_float(f), do: :erlang.float_to_binary(f, decimals: 2)
end
