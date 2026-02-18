defmodule Kerto.Engine.Applier do
  @moduledoc """
  Bridges Level 1 ExtractionOps to Level 0 Graph mutations.

  Pure function — takes a graph and ops, returns a new graph.
  No ETS, no GenServer, no side effects.
  """

  alias Kerto.Graph.{Graph, Identity, Relationship}

  @spec apply_ops(Graph.t(), [tuple()], String.t()) :: Graph.t()
  def apply_ops(%Graph{} = graph, ops, ulid) when is_list(ops) and is_binary(ulid) do
    Enum.reduce(ops, graph, fn op, acc -> apply_op(acc, op, ulid) end)
  end

  defp apply_op(graph, {:upsert_node, %{kind: kind, name: name, confidence: confidence}}, ulid) do
    {graph, _node} = Graph.upsert_node(graph, kind, name, confidence, ulid)
    graph
  end

  defp apply_op(graph, {:upsert_relationship, attrs}, ulid) do
    %{
      source_kind: source_kind,
      source_name: source_name,
      relation: relation,
      target_kind: target_kind,
      target_name: target_name,
      confidence: confidence,
      evidence: evidence
    } = attrs

    source_id = Identity.compute_id(source_kind, source_name)
    target_id = Identity.compute_id(target_kind, target_name)

    {graph, _rel} =
      Graph.upsert_relationship(graph, source_id, relation, target_id, confidence, ulid, evidence)

    graph
  end

  defp apply_op(graph, {:weaken_relationship, attrs}, _ulid) do
    %{
      source_kind: source_kind,
      source_name: source_name,
      relation: relation,
      target_kind: target_kind,
      target_name: target_name,
      factor: factor
    } = attrs

    source_id = Identity.compute_id(source_kind, source_name)
    target_id = Identity.compute_id(target_kind, target_name)
    key = {source_id, relation, target_id}

    case Map.get(graph.relationships, key) do
      nil ->
        graph

      rel ->
        weakened = Relationship.weaken(rel, factor)
        %{graph | relationships: Map.put(graph.relationships, key, weakened)}
    end
  end
end
