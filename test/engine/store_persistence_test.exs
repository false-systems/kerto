defmodule Kerto.Engine.StorePersistenceTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.{Persistence, Store}
  alias Kerto.Graph.Graph
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(type, data, ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new(type, data, source)
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "kerto_store_test_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "persists graph after ingest", %{tmp: tmp} do
    store = start_supervised!({Store, name: :test_persist_store, persistence_path: tmp})

    occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
    Store.ingest(store, occ)

    path = Persistence.path(tmp)
    assert File.exists?(path)

    loaded = Persistence.load(path)
    assert Graph.node_count(loaded) >= 1
  end

  test "loads persisted graph on restart", %{tmp: tmp} do
    store1 = start_supervised!({Store, name: :test_persist_restart, persistence_path: tmp})
    occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
    Store.ingest(store1, occ)
    stop_supervised!(Store)

    store2 = start_supervised!({Store, name: :test_persist_restart2, persistence_path: tmp})
    assert {:ok, node} = Store.get_node(store2, :file, "auth.go")
    assert node.name == "auth.go"
  end

  test "persistence_path nil skips I/O" do
    store = start_supervised!({Store, name: :test_no_persist, persistence_path: nil})

    occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
    assert :ok = Store.ingest(store, occ)
    assert {:ok, _} = Store.get_node(store, :file, "auth.go")
  end

  test "persists after decay", %{tmp: tmp} do
    store = start_supervised!({Store, name: :test_persist_decay, persistence_path: tmp})

    occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
    Store.ingest(store, occ)
    Store.decay(store, 0.5)

    loaded = Persistence.load(Persistence.path(tmp))
    {:ok, node} = Graph.get_node(loaded, Kerto.Graph.Identity.compute_id(:file, "auth.go"))
    assert node.relevance < 0.5
  end
end
