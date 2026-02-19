defmodule Kerto.Interface.Command.DeleteTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Delete
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_delete_engine, decay_interval_ms: :timer.hours(1)}
    )

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(:test_delete_engine, occ)
    %{engine: :test_delete_engine}
  end

  test "deletes a node", %{engine: engine} do
    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "auth.go")

    resp = Delete.execute(engine, %{node: "auth.go", kind: :file})
    assert resp.ok

    assert :error = Kerto.Engine.get_node(engine, :file, "auth.go")
  end

  test "returns error for missing node", %{engine: engine} do
    resp = Delete.execute(engine, %{node: "nope.go", kind: :file})
    refute resp.ok
    assert resp.error == :not_found
  end

  test "deletes a relationship", %{engine: engine} do
    resp =
      Delete.execute(engine, %{
        source: "auth.go",
        source_kind: :file,
        relation: :breaks,
        target: "test",
        target_kind: :module
      })

    assert resp.ok
  end

  test "returns error when neither node nor relationship args given", %{engine: engine} do
    resp = Delete.execute(engine, %{})
    refute resp.ok
  end
end
