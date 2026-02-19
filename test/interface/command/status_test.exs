defmodule Kerto.Interface.Command.StatusTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Status
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    engine =
      start_supervised!(
        {Kerto.Engine, name: :test_status_engine, decay_interval_ms: :timer.hours(1)}
      )

    %{engine: :test_status_engine}
  end

  test "returns status of empty engine", %{engine: engine} do
    resp = Status.execute(engine, %{})
    assert resp.ok
    assert resp.data.nodes == 0
    assert resp.data.relationships == 0
    assert resp.data.occurrences == 0
  end

  test "reflects state after ingest", %{engine: engine} do
    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("t", "a", "01JABC")
      )

    Kerto.Engine.ingest(engine, occ)

    resp = Status.execute(engine, %{})
    assert resp.ok
    assert resp.data.nodes >= 1
    assert resp.data.occurrences == 1
  end
end
