defmodule Kerto.Engine.EngineTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(type, data, ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new(type, data, source)
  end

  setup do
    engine = start_supervised!({Engine, name: :test_engine, decay_interval_ms: :timer.hours(1)})
    %{engine: engine}
  end

  describe "ingest/2" do
    test "ingests occurrence into store and log" do
      occ =
        make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")

      assert :ok = Engine.ingest(:test_engine, occ)
      assert {:ok, _node} = Engine.get_node(:test_engine, :file, "auth.go")
      assert Engine.occurrence_count(:test_engine) == 1
    end

    test "ingests multiple occurrences" do
      occ1 = make_occurrence("ci.run.failed", %{files: ["a.go"], task: "test"}, "01JAAA")
      occ2 = make_occurrence("vcs.commit", %{files: ["b.go", "c.go"], message: "fix"}, "01JBBB")

      Engine.ingest(:test_engine, occ1)
      Engine.ingest(:test_engine, occ2)

      assert Engine.node_count(:test_engine) >= 3
      assert Engine.occurrence_count(:test_engine) == 2
    end
  end

  describe "get_node/3" do
    test "returns node after ingest" do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Engine.ingest(:test_engine, occ)

      assert {:ok, node} = Engine.get_node(:test_engine, :file, "auth.go")
      assert node.name == "auth.go"
    end

    test "returns :error for missing node" do
      assert :error = Engine.get_node(:test_engine, :file, "nope.go")
    end
  end

  describe "occurrences_since/2" do
    test "returns all occurrences when nil" do
      occ1 = make_occurrence("ci.run.failed", %{files: ["a.go"], task: "test"}, "01JAAA")
      occ2 = make_occurrence("ci.run.failed", %{files: ["b.go"], task: "test"}, "01JBBB")

      Engine.ingest(:test_engine, occ1)
      Engine.ingest(:test_engine, occ2)

      result = Engine.occurrences_since(:test_engine, nil)
      assert length(result) == 2
    end

    test "returns occurrences after sync point" do
      occ1 = make_occurrence("ci.run.failed", %{files: ["a.go"], task: "test"}, "01JAAA")
      occ2 = make_occurrence("ci.run.failed", %{files: ["b.go"], task: "test"}, "01JBBB")

      Engine.ingest(:test_engine, occ1)
      Engine.ingest(:test_engine, occ2)

      result = Engine.occurrences_since(:test_engine, "01JAAA")
      assert length(result) == 1
      assert hd(result).source.ulid == "01JBBB"
    end
  end

  describe "status/1" do
    test "returns engine status" do
      status = Engine.status(:test_engine)
      assert Map.has_key?(status, :nodes)
      assert Map.has_key?(status, :relationships)
      assert Map.has_key?(status, :occurrences)
    end

    test "status reflects state after ingest" do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Engine.ingest(:test_engine, occ)

      status = Engine.status(:test_engine)
      assert status.nodes >= 1
      assert status.occurrences == 1
    end
  end

  describe "decay/2" do
    test "decay reduces relevance via engine facade" do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Engine.ingest(:test_engine, occ)

      {:ok, before} = Engine.get_node(:test_engine, :file, "auth.go")
      Engine.decay(:test_engine, 0.5)
      {:ok, after_decay} = Engine.get_node(:test_engine, :file, "auth.go")

      assert after_decay.relevance < before.relevance
    end
  end

  describe "supervision" do
    test "store survives decay process crash" do
      occ = make_occurrence("ci.run.failed", %{files: ["auth.go"], task: "test"}, "01JABC")
      Engine.ingest(:test_engine, occ)

      # Kill the decay process
      decay_pid = Process.whereis(:"test_engine.decay")
      assert is_pid(decay_pid)
      Process.exit(decay_pid, :kill)

      # Wait for supervisor to restart it
      Process.sleep(50)

      # Store still works
      assert {:ok, _node} = Engine.get_node(:test_engine, :file, "auth.go")

      # Decay process was restarted
      new_decay_pid = Process.whereis(:"test_engine.decay")
      assert is_pid(new_decay_pid)
      assert new_decay_pid != decay_pid
    end
  end
end
