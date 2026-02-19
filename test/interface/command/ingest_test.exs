defmodule Kerto.Interface.Command.IngestTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Ingest

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_ingest_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_ingest_engine}
  end

  test "ingests a CI failure occurrence", %{engine: engine} do
    args = %{
      type: "ci.run.failed",
      data: %{files: ["auth.go"], task: "test"},
      source: %{system: "sykli", agent: "ci", ulid: "01JABC"}
    }

    resp = Ingest.execute(engine, args)
    assert resp.ok
    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "auth.go")
  end

  test "generates source when not provided", %{engine: engine} do
    args = %{type: "ci.run.failed", data: %{files: ["b.go"], task: "test"}}
    resp = Ingest.execute(engine, args)
    assert resp.ok
    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "b.go")
  end

  test "returns error when type is missing", %{engine: engine} do
    resp = Ingest.execute(engine, %{data: %{}})
    refute resp.ok
    assert resp.error =~ "type"
  end

  test "defaults data to empty map", %{engine: engine} do
    args = %{type: "unknown.type"}
    resp = Ingest.execute(engine, args)
    assert resp.ok
  end
end
