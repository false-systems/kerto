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
end
