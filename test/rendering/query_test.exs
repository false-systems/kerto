defmodule Kerto.Rendering.QueryTest do
  use ExUnit.Case, async: true

  alias Kerto.Rendering.Query
  alias Kerto.Graph.{Graph, Identity}

  defp build_graph do
    graph = Graph.new()

    # auth.go breaks login_test.go
    {graph, _} = Graph.upsert_node(graph, :file, "auth.go", 0.8, "01J001")
    {graph, _} = Graph.upsert_node(graph, :file, "login_test.go", 0.8, "01J001")
    {graph, _} = Graph.upsert_node(graph, :decision, "JWT", 0.9, "01J001")
    {graph, _} = Graph.upsert_node(graph, :file, "auth_test.go", 0.8, "01J001")

    auth_id = Identity.compute_id(:file, "auth.go")
    test_id = Identity.compute_id(:file, "login_test.go")
    jwt_id = Identity.compute_id(:decision, "JWT")
    auth_test_id = Identity.compute_id(:file, "auth_test.go")

    {graph, _} =
      Graph.upsert_relationship(graph, auth_id, :breaks, test_id, 0.8, "01J001", "CI failure")

    {graph, _} =
      Graph.upsert_relationship(graph, auth_id, :decided, jwt_id, 0.9, "01J001", "chose JWT")

    {graph, _} =
      Graph.upsert_relationship(
        graph,
        auth_id,
        :often_changes_with,
        auth_test_id,
        0.7,
        "01J001",
        "co-change"
      )

    graph
  end

  describe "query_context/5" do
    test "returns context for existing node" do
      graph = build_graph()
      assert {:ok, ctx} = Query.query_context(graph, :file, "auth.go", "01J002")
      assert ctx.node.name == "auth.go"
    end

    test "returns :not_found for missing node" do
      graph = build_graph()
      assert {:error, :not_found} = Query.query_context(graph, :file, "missing.go", "01J002")
    end

    test "includes relationships at depth 1" do
      graph = build_graph()
      {:ok, ctx} = Query.query_context(graph, :file, "auth.go", "01J002")
      assert length(ctx.relationships) == 3
    end

    test "node_lookup contains neighbor nodes" do
      graph = build_graph()
      {:ok, ctx} = Query.query_context(graph, :file, "auth.go", "01J002")

      test_id = Identity.compute_id(:file, "login_test.go")
      assert Map.has_key?(ctx.node_lookup, test_id)
    end

    test "node_lookup contains focal node" do
      graph = build_graph()
      {:ok, ctx} = Query.query_context(graph, :file, "auth.go", "01J002")

      auth_id = Identity.compute_id(:file, "auth.go")
      assert Map.has_key?(ctx.node_lookup, auth_id)
    end

    test "respects depth option" do
      graph = Graph.new()
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "c.go", 0.8, "01J001")

      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      c = Identity.compute_id(:file, "c.go")

      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")
      {graph, _} = Graph.upsert_relationship(graph, b, :breaks, c, 0.8, "01J001", "e2")

      # Depth 1 should only get a->b
      {:ok, ctx} = Query.query_context(graph, :file, "a.go", "01J002", depth: 1)
      assert length(ctx.relationships) == 1

      # Depth 2 should get both
      {:ok, ctx} = Query.query_context(graph, :file, "a.go", "01J002", depth: 2)
      assert length(ctx.relationships) == 2
    end

    test "default depth is 2" do
      graph = Graph.new()
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "c.go", 0.8, "01J001")

      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")
      c = Identity.compute_id(:file, "c.go")

      {graph, _} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e1")
      {graph, _} = Graph.upsert_relationship(graph, b, :breaks, c, 0.8, "01J001", "e2")

      {:ok, ctx} = Query.query_context(graph, :file, "a.go", "01J002")
      # Default depth 2 should reach c
      assert length(ctx.relationships) == 2
    end

    test "empty graph returns not_found" do
      graph = Graph.new()
      assert {:error, :not_found} = Query.query_context(graph, :file, "auth.go", "01J002")
    end

    test "isolated node returns context with no relationships" do
      graph = Graph.new()
      {graph, _} = Graph.upsert_node(graph, :file, "lonely.go", 0.8, "01J001")

      {:ok, ctx} = Query.query_context(graph, :file, "lonely.go", "01J002")
      assert ctx.relationships == []
      assert ctx.node.name == "lonely.go"
    end

    test "passes min_weight through to subgraph" do
      graph = Graph.new()
      {graph, _} = Graph.upsert_node(graph, :file, "a.go", 0.8, "01J001")
      {graph, _} = Graph.upsert_node(graph, :file, "b.go", 0.8, "01J001")

      a = Identity.compute_id(:file, "a.go")
      b = Identity.compute_id(:file, "b.go")

      {graph, rel} = Graph.upsert_relationship(graph, a, :breaks, b, 0.8, "01J001", "e")

      # Weaken the relationship to near zero
      weakened = Kerto.Graph.Relationship.weaken(rel, 0.01)
      key = {a, :breaks, b}
      graph = %{graph | relationships: Map.put(graph.relationships, key, weakened)}

      {:ok, ctx} = Query.query_context(graph, :file, "a.go", "01J002", min_weight: 0.1)
      assert ctx.relationships == []
    end

    test "context node has correct kind" do
      graph = build_graph()
      {:ok, ctx} = Query.query_context(graph, :file, "auth.go", "01J002")
      assert ctx.node.kind == :file
    end
  end
end
