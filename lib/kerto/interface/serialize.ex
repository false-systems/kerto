defmodule Kerto.Interface.Serialize do
  @moduledoc """
  Shared serialization for converting domain structs to JSON-safe maps.

  Used by commands that return structured data (list, context, grep, graph).
  """

  alias Kerto.Graph.{Node, Relationship}

  @spec node_to_map(Node.t()) :: map()
  def node_to_map(%Node{} = node) do
    %{
      id: node.id,
      name: node.name,
      kind: Atom.to_string(node.kind),
      relevance: node.relevance,
      observations: node.observations,
      first_seen: node.first_seen,
      last_seen: node.last_seen,
      pinned: Map.get(node, :pinned, false),
      summary: Map.get(node, :summary)
    }
  end

  @spec rel_to_map(Relationship.t(), map()) :: map()
  def rel_to_map(%Relationship{} = rel, node_lookup) when is_map(node_lookup) do
    %{
      source: rel.source,
      target: rel.target,
      source_name: resolve_name(rel.source, node_lookup),
      target_name: resolve_name(rel.target, node_lookup),
      relation: Atom.to_string(rel.relation),
      weight: rel.weight,
      observations: rel.observations,
      first_seen: rel.first_seen,
      last_seen: rel.last_seen,
      evidence: rel.evidence,
      pinned: Map.get(rel, :pinned, false)
    }
  end

  @spec to_json_safe(term()) :: term()
  def to_json_safe(val) when is_atom(val) and val not in [nil, true, false],
    do: Atom.to_string(val)

  def to_json_safe(val) when is_map(val) do
    Map.new(val, fn {k, v} -> {to_json_safe(k), to_json_safe(v)} end)
  end

  def to_json_safe(val) when is_list(val), do: Enum.map(val, &to_json_safe/1)
  def to_json_safe(val), do: val

  defp resolve_name(id, lookup) do
    case Map.get(lookup, id) do
      nil -> id
      %{name: name} -> name
    end
  end
end
