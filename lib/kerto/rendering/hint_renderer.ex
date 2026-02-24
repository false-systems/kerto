defmodule Kerto.Rendering.HintRenderer do
  @moduledoc """
  Compact renderer for pre-tool-use hints.

  Produces short, actionable hints from rendering Contexts.
  Priority: Caution first, then Knowledge, skip Structure.
  Max 5 lines, max 500 chars total.
  """

  alias Kerto.Rendering.Context

  @caution_relations [:breaks, :caused_by, :triggers]
  @knowledge_relations [:learned, :decided, :tried_failed]
  @max_lines 5
  @max_chars 500

  @spec render([Context.t()]) :: String.t()
  def render(contexts) when is_list(contexts) do
    contexts
    |> Enum.flat_map(&extract_hints/1)
    |> Enum.uniq_by(fn {node_name, relation, other_name, _weight, _obs} ->
      {node_name, relation, other_name}
    end)
    |> sort_hints()
    |> Enum.group_by(fn {node_name, _rel, _other, _w, _obs} -> node_name end)
    |> Enum.flat_map(fn {node_name, hints} ->
      parts =
        Enum.map(hints, fn {_node_name, relation, other_name, weight, obs} ->
          "#{relation} #{other_name} (#{format_float(weight)}, #{obs}x)"
        end)

      ["[kerto] #{node_name}: #{Enum.join(parts, " | ")}"]
    end)
    |> Enum.take(@max_lines)
    |> truncate_chars()
    |> Enum.join("\n")
  end

  defp extract_hints(%Context{} = ctx) do
    caution = extract_by_relations(ctx, @caution_relations, :caution)
    knowledge = extract_by_relations(ctx, @knowledge_relations, :knowledge)
    caution ++ knowledge
  end

  defp extract_by_relations(ctx, relations, _group) do
    ctx.relationships
    |> Enum.filter(&(&1.relation in relations))
    |> Enum.sort_by(& &1.weight, :desc)
    |> Enum.map(fn rel ->
      other_id = if rel.source == ctx.node.id, do: rel.target, else: rel.source

      other_name =
        case Map.get(ctx.node_lookup, other_id) do
          nil -> other_id
          node -> node.name
        end

      {ctx.node.name, rel.relation, other_name, rel.weight, rel.observations}
    end)
  end

  defp sort_hints(hints) do
    Enum.sort_by(hints, fn {_name, relation, _other, weight, _obs} ->
      priority = if relation in @caution_relations, do: 0, else: 1
      {priority, -weight}
    end)
  end

  defp truncate_chars(lines) do
    {result, _remaining} =
      Enum.reduce(lines, {[], @max_chars}, fn line, {acc, remaining} ->
        len = byte_size(line)

        if len <= remaining do
          {acc ++ [line], remaining - len - 1}
        else
          {acc, 0}
        end
      end)

    result
  end

  defp format_float(f), do: :erlang.float_to_binary(f, decimals: 2)
end
