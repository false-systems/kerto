defmodule Kerto.Engine.PersistenceTest do
  use ExUnit.Case, async: true

  alias Kerto.Engine.Persistence
  alias Kerto.Graph.Graph

  setup do
    tmp = Path.join(System.tmp_dir!(), "kerto_test_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "save/2 and load/1" do
    test "round-trips a graph with nodes and relationships", %{tmp: tmp} do
      path = Persistence.path(tmp)

      {graph, _} = Graph.upsert_node(Graph.new(), :file, "auth.go", 0.8, "01JABC")
      {graph, _} = Graph.upsert_node(graph, :module, "api", 0.7, "01JABC")

      source_id = Kerto.Graph.Identity.compute_id(:file, "auth.go")
      target_id = Kerto.Graph.Identity.compute_id(:module, "api")

      {graph, _} =
        Graph.upsert_relationship(
          graph,
          source_id,
          :depends_on,
          target_id,
          0.8,
          "01JABC",
          "evidence"
        )

      :ok = Persistence.save(graph, path)
      loaded = Persistence.load(path)

      assert Graph.node_count(loaded) == 2
      assert Graph.relationship_count(loaded) == 1
      assert {:ok, node} = Graph.get_node(loaded, source_id)
      assert node.name == "auth.go"
    end

    test "load returns empty graph for missing file" do
      graph = Persistence.load("/tmp/kerto_nonexistent_#{:rand.uniform(999_999)}/graph.etf")
      assert %Graph{} = graph
      assert Graph.node_count(graph) == 0
    end

    test "load returns empty graph for corrupt file", %{tmp: tmp} do
      path = Persistence.path(tmp)
      File.mkdir_p!(tmp)
      File.write!(path, "not valid ETF data")

      graph = Persistence.load(path)
      assert %Graph{} = graph
      assert Graph.node_count(graph) == 0
    end

    test "save creates nested directories", %{tmp: tmp} do
      nested = Path.join([tmp, "deep", "nested"])
      path = Persistence.path(nested)

      :ok = Persistence.save(Graph.new(), path)
      assert File.exists?(path)
    end
  end

  describe "path/1" do
    test "returns graph.etf under base dir" do
      assert Persistence.path("/some/dir") == "/some/dir/graph.etf"
    end
  end
end
