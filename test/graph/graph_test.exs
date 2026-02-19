defmodule Kerto.Graph.GraphTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.{Graph, Identity}

  setup do
    {:ok, graph: Graph.new()}
  end

  describe "new/0" do
    test "creates empty graph", %{graph: graph} do
      assert Graph.node_count(graph) == 0
      assert Graph.relationship_count(graph) == 0
    end
  end

  describe "upsert_node/3" do
    test "adds a new node", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      assert Graph.node_count(graph) == 1
    end

    test "returns the node", %{graph: graph} do
      {_graph, node} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      assert node.name == "auth.go"
      assert node.kind == :file
    end

    test "deduplicates by content address", %{graph: graph} do
      {graph, _node} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _node} = Graph.upsert_node(graph, :file, "auth.go", 0.9, "01JDEF")
      assert Graph.node_count(graph) == 1
    end

    test "reinforces existing node on upsert", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {_graph, node} = Graph.upsert_node(graph, :file, "auth.go", 1.0, "01JDEF")
      assert node.observations == 2
      assert node.last_seen == "01JDEF"
    end
  end

  describe "upsert_relationship/6" do
    test "adds a new relationship", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "login_test.go")

      {graph, _} =
        Graph.upsert_relationship(
          graph,
          source_id,
          :breaks,
          target_id,
          0.8,
          "01JABC",
          "CI linked"
        )

      assert Graph.relationship_count(graph) == 1
    end

    test "deduplicates by composite key", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "login_test.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.8, "01JABC", "first")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.9, "01JDEF", "second")

      assert Graph.relationship_count(graph) == 1
    end

    test "reinforces existing relationship", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "login_test.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.8, "01JABC", "first")

      {_graph, rel} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.9, "01JDEF", "second")

      assert rel.observations == 2
      assert rel.evidence == ["first", "second"]
    end
  end

  describe "get_node/2" do
    test "returns node by id", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      id = Identity.compute_id(:file, "auth.go")
      assert {:ok, node} = Graph.get_node(graph, id)
      assert node.name == "auth.go"
    end

    test "returns error for missing node", %{graph: graph} do
      assert :error = Graph.get_node(graph, "nonexistent")
    end
  end

  describe "neighbors/3" do
    test "returns outgoing relationships for a node", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "session.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target1 = Identity.compute_id(:file, "login_test.go")
      target2 = Identity.compute_id(:file, "session.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target1, 0.8, "01JABC", "e1")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :depends_on, target2, 0.7, "01JABC", "e2")

      rels = Graph.neighbors(graph, source_id, :outgoing)
      assert length(rels) == 2
    end

    test "returns incoming relationships for a node", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "login_test.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.8, "01JABC", "e1")

      rels = Graph.neighbors(graph, target_id, :incoming)
      assert length(rels) == 1
      assert hd(rels).source == source_id
    end
  end

  describe "decay_all/2" do
    test "decays all nodes and relationships", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "test.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.8, "01JABC", "e")

      decayed = Graph.decay_all(graph, 0.5)

      {:ok, node} = Graph.get_node(decayed, source_id)
      # Initial relevance 0.5 * decay 0.5 = 0.25
      assert_in_delta node.relevance, 0.25, 0.001
    end

    test "prunes dead relationships", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :file, "test.go", 0.8, "01JABC")
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "test.go")

      {graph, _} =
        Graph.upsert_relationship(graph, source_id, :breaks, target_id, 0.8, "01JABC", "e")

      # Aggressive decay to kill the relationship
      decayed = Enum.reduce(1..100, graph, fn _, g -> Graph.decay_all(g, 0.8) end)
      assert Graph.relationship_count(decayed) == 0
    end
  end

  describe "subgraph/3" do
    setup %{graph: graph} do
      # Build a small graph: A -> B -> C -> D, A -> E
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "c.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "d.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :module, "tests", 0.8, "01J001")

      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      c = Identity.compute_id(:file, "c.go")
      d = Identity.compute_id(:file, "d.go")
      e = Identity.compute_id(:module, "tests")

      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")
      {graph, _} = Graph.upsert_relationship(graph, b, :breaks, c, 0.8, "01J001", "e2")
      {graph, _} = Graph.upsert_relationship(graph, c, :breaks, d, 0.8, "01J001", "e3")
      {graph, _} = Graph.upsert_relationship(graph, a, :depends_on, e, 0.8, "01J001", "e4")

      {:ok, graph: graph, ids: %{a: a, b: b, c: c, d: d, e: e}}
    end

    test "returns root node and immediate neighbors at depth 1", %{graph: graph, ids: ids} do
      {nodes, rels} = Graph.subgraph(graph, ids.a, depth: 1)
      node_ids = Enum.map(nodes, & &1.id) |> MapSet.new()

      assert MapSet.member?(node_ids, ids.a)
      assert MapSet.member?(node_ids, ids.b)
      assert MapSet.member?(node_ids, ids.e)
      assert MapSet.size(node_ids) == 3
      assert length(rels) == 2
    end

    test "traverses to depth 2", %{graph: graph, ids: ids} do
      {nodes, rels} = Graph.subgraph(graph, ids.a, depth: 2)
      node_ids = Enum.map(nodes, & &1.id) |> MapSet.new()

      assert MapSet.member?(node_ids, ids.a)
      assert MapSet.member?(node_ids, ids.b)
      assert MapSet.member?(node_ids, ids.c)
      assert MapSet.member?(node_ids, ids.e)
      assert MapSet.size(node_ids) == 4
      assert length(rels) == 3
    end

    test "returns empty for missing node", %{graph: graph} do
      {nodes, rels} = Graph.subgraph(graph, "nonexistent", depth: 2)
      assert nodes == []
      assert rels == []
    end

    test "filters relationships below min_weight", %{graph: graph, ids: ids} do
      # Add a weak relationship
      {graph, _} = Graph.upsert_node(graph, :file, "weak.go", 0.8, "01J001")
      weak_id = Identity.compute_id(:file, "weak.go")

      {graph, rel} =
        Graph.upsert_relationship(graph, ids.a, :learned, weak_id, 0.1, "01J001", "weak")

      # Weaken it heavily so weight is very low
      weakened = Kerto.Graph.Relationship.weaken(rel, 0.01)
      key = {ids.a, :learned, weak_id}
      graph = %{graph | relationships: Map.put(graph.relationships, key, weakened)}

      {nodes, _rels} = Graph.subgraph(graph, ids.a, depth: 1, min_weight: 0.1)
      node_ids = Enum.map(nodes, & &1.id) |> MapSet.new()

      refute MapSet.member?(node_ids, weak_id)
    end

    test "depth 0 returns only root node", %{graph: graph, ids: ids} do
      {nodes, rels} = Graph.subgraph(graph, ids.a, depth: 0)
      assert length(nodes) == 1
      assert hd(nodes).id == ids.a
      assert rels == []
    end

    test "follows both outgoing and incoming edges", %{graph: graph, ids: ids} do
      # Query from B — should find A (incoming) and C (outgoing)
      {nodes, _rels} = Graph.subgraph(graph, ids.b, depth: 1)
      node_ids = Enum.map(nodes, & &1.id) |> MapSet.new()

      assert MapSet.member?(node_ids, ids.a)
      assert MapSet.member?(node_ids, ids.b)
      assert MapSet.member?(node_ids, ids.c)
    end

    test "does not revisit nodes", %{graph: graph, ids: ids} do
      # Add a cycle: E -> A
      {graph, _} =
        Graph.upsert_relationship(graph, ids.e, :triggers, ids.a, 0.8, "01J001", "cycle")

      {nodes, _rels} = Graph.subgraph(graph, ids.a, depth: 3)
      node_ids = Enum.map(nodes, & &1.id)

      # No duplicates
      assert length(node_ids) == length(Enum.uniq(node_ids))
    end

    test "default min_weight is 0.0", %{graph: graph, ids: ids} do
      {nodes, _rels} = Graph.subgraph(graph, ids.a, depth: 1)
      # All neighbors included regardless of weight
      assert length(nodes) == 3
    end
  end

  describe "delete_node/2" do
    test "removes node and all its relationships", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")

      {graph, :ok} = Graph.delete_node(graph, a)
      assert Graph.node_count(graph) == 1
      assert Graph.relationship_count(graph) == 0
    end

    test "returns error for missing node", %{graph: graph} do
      assert {^graph, :error} = Graph.delete_node(graph, "nonexistent")
    end

    test "removes relationships where node is target", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")

      {graph, :ok} = Graph.delete_node(graph, b)
      assert Graph.node_count(graph) == 1
      assert Graph.relationship_count(graph) == 0
    end
  end

  describe "delete_relationship/2" do
    test "removes a specific relationship", %{graph: graph} do
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")

      {graph, :ok} = Graph.delete_relationship(graph, {a, :breaks, b})
      assert Graph.relationship_count(graph) == 0
      assert Graph.node_count(graph) == 2
    end

    test "returns error for missing relationship", %{graph: graph} do
      assert {^graph, :error} = Graph.delete_relationship(graph, {"x", :breaks, "y"})
    end
  end
end
