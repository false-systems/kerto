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

  test "returns rendered context for known entity", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go", kind: :file})
    assert resp.ok
    assert resp.data =~ "auth.go"
    assert resp.data =~ "file"
  end

  test "defaults kind to :file", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go"})
    assert resp.ok
    assert resp.data =~ "auth.go"
  end

  test "returns error for unknown entity", %{engine: engine} do
    resp = Context.execute(engine, %{name: "nope.go", kind: :file})
    refute resp.ok
    assert resp.error == :not_found
  end

  test "passes depth and min_weight options", %{engine: engine} do
    resp = Context.execute(engine, %{name: "auth.go", kind: :file, depth: 1, min_weight: 0.0})
    assert resp.ok
  end

  test "returns error when name is missing", %{engine: engine} do
    resp = Context.execute(engine, %{})
    refute resp.ok
    assert resp.error =~ "name"
  end
end
