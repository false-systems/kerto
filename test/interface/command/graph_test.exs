defmodule Kerto.Interface.Command.GraphTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_graph_engine, decay_interval_ms: :timer.hours(1)}
    )

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(:test_graph_engine, occ)
    %{engine: :test_graph_engine}
  end

  test "returns JSON format by default", %{engine: engine} do
    resp = Command.Graph.execute(engine, %{})
    assert resp.ok
    assert is_list(resp.data.nodes)
    assert is_list(resp.data.relationships)
    assert length(resp.data.nodes) >= 1
  end

  test "returns DOT format", %{engine: engine} do
    resp = Command.Graph.execute(engine, %{format: :dot})
    assert resp.ok
    assert resp.data =~ "digraph kerto"
    assert resp.data =~ "->"
  end

  test "returns error for unknown format", %{engine: engine} do
    resp = Command.Graph.execute(engine, %{format: :xml})
    refute resp.ok
  end

  test "JSON nodes have expected fields", %{engine: engine} do
    resp = Command.Graph.execute(engine, %{format: :json})
    node = hd(resp.data.nodes)
    assert Map.has_key?(node, :name)
    assert Map.has_key?(node, :kind)
    assert Map.has_key?(node, :relevance)
    assert Map.has_key?(node, :observations)
  end
end
