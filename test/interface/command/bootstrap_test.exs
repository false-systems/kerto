defmodule Kerto.Interface.Command.BootstrapTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Bootstrap
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_bootstrap_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_bootstrap_engine}
  end

  test "skips bootstrap when graph has more than 10 nodes", %{engine: engine} do
    source = Source.new("t", "a", "01JABC")

    for i <- 1..11 do
      occ =
        Occurrence.new(
          "vcs.commit",
          %{files: ["file_#{i}.ex"], message: "m"},
          source
        )

      Kerto.Engine.ingest(engine, occ)
    end

    assert Kerto.Engine.node_count(engine) > 10
    resp = Bootstrap.execute(engine, %{})
    assert resp.ok
    assert resp.data =~ "skipped"
  end

  test "runs bootstrap on empty graph (requires git repo)", %{engine: engine} do
    resp = Bootstrap.execute(engine, %{})
    assert resp.ok
    assert resp.data =~ "bootstrap complete"
  end
end
