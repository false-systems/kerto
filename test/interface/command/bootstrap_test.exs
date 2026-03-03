defmodule Kerto.Interface.Command.BootstrapTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.Persistence
  alias Kerto.Interface.Command.Bootstrap
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    tmp = Path.join(System.tmp_dir!(), "kerto_bootstrap_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)

    start_supervised!(
      {Kerto.Engine,
       name: :test_bootstrap_engine, persistence_path: tmp, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_bootstrap_engine, tmp: tmp}
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

  test "clears graph and re-bootstraps on fingerprint mismatch", %{engine: engine, tmp: tmp} do
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

    # Write a fake fingerprint that won't match the real repo
    Persistence.save_fingerprint(tmp, "fake_root_commit_hash")

    resp = Bootstrap.execute(engine, %{})
    assert resp.ok
    assert resp.data =~ "re-bootstrap"

    # Fingerprint should now match the real repo
    stored = Persistence.load_fingerprint(tmp)
    assert stored != "fake_root_commit_hash"
    assert stored != nil
  end

  test "saves fingerprint after first bootstrap", %{engine: engine, tmp: tmp} do
    assert Persistence.load_fingerprint(tmp) == nil

    resp = Bootstrap.execute(engine, %{})
    assert resp.ok

    assert Persistence.load_fingerprint(tmp) != nil
  end
end
