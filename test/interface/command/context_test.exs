defmodule Kerto.Interface.Command.ContextTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Context
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!({Kerto.Engine, name: :test_ctx_engine, decay_interval_ms: :timer.hours(1)})

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(:test_ctx_engine, occ)
    %{engine: :test_ctx_engine}
  end

  test "returns structured context for known entity", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go", kind: :file})
    assert resp.ok
    assert resp.data.node.name == "auth.go"
    assert resp.data.node.kind == "file"
    assert is_list(resp.data.relationships)
    assert is_binary(resp.data.rendered)
    assert resp.data.rendered =~ "auth.go"
  end

  test "defaults kind to :file", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go"})
    assert resp.ok
    assert resp.data.node.name == "auth.go"
  end

  test "returns error for unknown entity with hint", %{engine: engine} do
    resp = Context.execute(engine, %{name: "nope.go", kind: :file})
    refute resp.ok
    assert resp.error =~ "not found"
  end

  test "context command includes hint on not_found", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth", kind: :file})
    refute resp.ok
    assert resp.error =~ "not found: auth (file)"
    assert resp.error =~ "Similar:"
    assert resp.error =~ "auth.go"
  end

  test "passes depth and min_weight options", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go", kind: :file, depth: 1, min_weight: 0.0})
    assert resp.ok
    assert resp.data.node.name == "auth.go"
  end

  test "returns error when name is missing", %{engine: engine} do
    resp = Context.execute(engine, %{})
    refute resp.ok
    assert resp.error =~ "name"
  end

  test "relationship maps include source and target names", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go", kind: :file, depth: 2})
    assert resp.ok

    Enum.each(resp.data.relationships, fn rel ->
      assert Map.has_key?(rel, :source_name)
      assert Map.has_key?(rel, :target_name)
      assert is_binary(rel.relation)
    end)
  end
end
