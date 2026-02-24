defmodule Kerto.Interface.Command.HintTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Hint
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!({Kerto.Engine, name: :test_hint_engine, decay_interval_ms: :timer.hours(1)})

    %{engine: :test_hint_engine}
  end

  test "returns empty string for unknown files", %{engine: engine} do
    resp = Hint.execute(engine, %{files: ["nonexistent.ex"]})
    assert resp.ok
    assert resp.data == ""
  end

  test "returns hints for files with caution relationships", %{engine: engine} do
    source = Source.new("test", "agent", "01JABC")

    occ =
      Occurrence.new(
        "context.learning",
        %{
          subject_kind: :file,
          subject_name: "auth.ex",
          relation: :breaks,
          target_kind: :file,
          target_name: "deploy.sh",
          evidence: "auth breaks deploy",
          confidence: 0.8
        },
        source
      )

    Kerto.Engine.ingest(engine, occ)

    resp = Hint.execute(engine, %{files: ["auth.ex"]})
    assert resp.ok
    assert resp.data =~ "auth.ex"
    assert resp.data =~ "breaks"
  end

  test "returns empty string for files with only structure relationships", %{engine: engine} do
    source = Source.new("test", "agent", "01JABC")

    occ =
      Occurrence.new(
        "bootstrap.file_tree",
        %{files: ["lib/auth.ex"]},
        source
      )

    Kerto.Engine.ingest(engine, occ)

    resp = Hint.execute(engine, %{files: ["lib/auth.ex"]})
    assert resp.ok
    assert resp.data == ""
  end

  test "handles comma-separated file string", %{engine: engine} do
    resp = Hint.execute(engine, %{files: "a.ex,b.ex"})
    assert resp.ok
  end

  test "handles empty files list", %{engine: engine} do
    resp = Hint.execute(engine, %{files: []})
    assert resp.ok
    assert resp.data == ""
  end
end
