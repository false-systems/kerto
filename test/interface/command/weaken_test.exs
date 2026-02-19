defmodule Kerto.Interface.Command.WeakenTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Weaken
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_weaken_engine, decay_interval_ms: :timer.hours(1)}
    )

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(:test_weaken_engine, occ)
    %{engine: :test_weaken_engine}
  end

  test "weakens an existing relationship", %{engine: engine} do
    resp =
      Weaken.execute(engine, %{
        source: "auth.go",
        source_kind: :file,
        relation: :breaks,
        target: "test",
        target_kind: :module,
        factor: 0.5
      })

    assert resp.ok
  end

  test "returns error when source is missing", %{engine: engine} do
    resp = Weaken.execute(engine, %{relation: :breaks, target: "test"})
    refute resp.ok
  end

  test "returns error when relation is missing", %{engine: engine} do
    resp = Weaken.execute(engine, %{source: "auth.go", target: "test"})
    refute resp.ok
  end

  test "returns error when target is missing", %{engine: engine} do
    resp = Weaken.execute(engine, %{source: "auth.go", relation: :breaks})
    refute resp.ok
  end
end
