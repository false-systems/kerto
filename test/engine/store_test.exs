defmodule Kerto.Engine.StoreTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.Store
  alias Kerto.Graph.Graph
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(type, data, ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new(type, data, source)
  end

  setup do
    store = start_supervised!({Store, name: :test_store})
    %{store: store}
  end

  describe "ingest/2" do
    test "ingests a CI failure occurrence", %{store: store} do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      assert :ok = Store.ingest(store, occ)

      assert {:ok, node} = Store.get_node(store, :file, "auth.go")
      assert node.kind == :file
      assert node.name == "auth.go"
    end

    test "ingests a commit occurrence", %{store: store} do
      occ =
        make_occurrence(
          "vcs.commit",
          %{files: ["a.go", "b.go"], message: "fix stuff"},
          "01JABC"
        )

      Store.ingest(store, occ)

      assert {:ok, _} = Store.get_node(store, :file, "a.go")
      assert {:ok, _} = Store.get_node(store, :file, "b.go")
    end

    test "multiple ingests reinforce nodes", %{store: store} do
      occ1 = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JAAA")
      occ2 = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JBBB")

      Store.ingest(store, occ1)
      Store.ingest(store, occ2)

      {:ok, node} = Store.get_node(store, :file, "auth.go")
      assert node.observations >= 2
    end

    test "unknown occurrence types are handled gracefully", %{store: store} do
      occ = make_occurrence("unknown.type", %{}, "01JABC")
      assert :ok = Store.ingest(store, occ)
    end
  end

  describe "get_node/3" do
    test "returns :error for missing node", %{store: store} do
      assert :error = Store.get_node(store, :file, "nope.go")
    end
  end

  describe "get_graph/1" do
    test "returns empty graph initially", %{store: store} do
      graph = Store.get_graph(store)
      assert %Graph{} = graph
      assert Graph.node_count(graph) == 0
    end

    test "returns graph with nodes after ingest", %{store: store} do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Store.ingest(store, occ)

      graph = Store.get_graph(store)
      assert Graph.node_count(graph) >= 1
    end
  end

  describe "decay/2" do
    test "reduces node relevance", %{store: store} do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Store.ingest(store, occ)

      {:ok, before} = Store.get_node(store, :file, "auth.go")
      Store.decay(store, 0.5)
      {:ok, after_decay} = Store.get_node(store, :file, "auth.go")

      assert after_decay.relevance < before.relevance
    end

    test "prunes dead relationships", %{store: store} do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Store.ingest(store, occ)

      # Aggressive decay to kill relationships
      for _ <- 1..50, do: Store.decay(store, 0.5)

      graph = Store.get_graph(store)
      assert Graph.relationship_count(graph) == 0
    end
  end

  describe "apply_ops/3 (for mesh replay)" do
    test "applies ops without going through extraction", %{store: store} do
      ops = [
        {:upsert_node, %{kind: :file, name: "remote.go", confidence: 0.8}},
        {:upsert_node, %{kind: :module, name: "api", confidence: 0.7}}
      ]

      Store.apply_ops(store, ops, "01JABC")

      assert {:ok, _} = Store.get_node(store, :file, "remote.go")
      assert {:ok, _} = Store.get_node(store, :module, "api")
    end
  end

  describe "node_count/1 and relationship_count/1" do
    test "returns counts", %{store: store} do
      assert Store.node_count(store) == 0
      assert Store.relationship_count(store) == 0

      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Store.ingest(store, occ)

      assert Store.node_count(store) >= 1
    end
  end
end
