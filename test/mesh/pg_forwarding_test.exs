defmodule Kerto.Mesh.PgForwardingTest do
  @moduledoc """
  Tests :pg-based event forwarding from Engine to Peer processes.
  """
  use ExUnit.Case, async: false

  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_pg_engine

  setup do
    # Ensure :pg is running (needed for peer group notifications)
    case :pg.start(:pg) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    :ok
  end

  test "ingest notifies :pg group members" do
    # Join the pg group as a subscriber
    Kerto.Engine.join_peer_group(@engine, self())

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["pg_test.go"], task: "test"},
        Source.new("test", "pg", "01JPGTEST")
      )

    Kerto.Engine.ingest(@engine, occ)

    assert_receive :new_occurrence, 1000

    # Cleanup
    Kerto.Engine.leave_peer_group(@engine, self())
  end

  test "ingest works fine with no :pg subscribers" do
    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["pg_test2.go"], task: "test"},
        Source.new("test", "pg", "01JPGTEST2")
      )

    # Should not raise or hang
    assert :ok = Kerto.Engine.ingest(@engine, occ)
  end
end
