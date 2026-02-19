defmodule Kerto.Interface.Command.DecayTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Decay
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_decay_cmd_engine, decay_interval_ms: :timer.hours(1)}
    )

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(:test_decay_cmd_engine, occ)
    %{engine: :test_decay_cmd_engine}
  end

  test "applies decay with default factor", %{engine: engine} do
    {:ok, before} = Kerto.Engine.get_node(engine, :file, "auth.go")
    resp = Decay.execute(engine, %{})
    assert resp.ok

    {:ok, after_decay} = Kerto.Engine.get_node(engine, :file, "auth.go")
    assert after_decay.relevance < before.relevance
  end

  test "applies decay with custom factor", %{engine: engine} do
    {:ok, before} = Kerto.Engine.get_node(engine, :file, "auth.go")
    resp = Decay.execute(engine, %{factor: 0.1})
    assert resp.ok

    {:ok, after_decay} = Kerto.Engine.get_node(engine, :file, "auth.go")
    assert after_decay.relevance < before.relevance * 0.2
  end
end
