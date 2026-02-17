defmodule Kerto.Mesh.SyncTest do
  use ExUnit.Case, async: true

  alias Kerto.Mesh.Sync
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(type, ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new(type, %{files: ["a.go"], task: "test"}, source)
  end

  describe "hello/2" do
    test "creates a hello message with sync point and node name" do
      msg = Sync.hello("01JABC", "kerto@dev-a")
      assert msg == {:sync_hello, "01JABC", "kerto@dev-a"}
    end

    test "nil sync point for first connection" do
      msg = Sync.hello(nil, "kerto@dev-a")
      assert msg == {:sync_hello, nil, "kerto@dev-a"}
    end
  end

  describe "live/0" do
    test "creates a live mode message" do
      assert Sync.live() == :sync_live
    end
  end

  describe "occurrences_since/2" do
    test "returns all occurrences when sync point is nil" do
      occs = [
        make_occurrence("ci.run.failed", "01JAAA"),
        make_occurrence("ci.run.passed", "01JBBB"),
        make_occurrence("vcs.commit", "01JCCC")
      ]

      result = Sync.occurrences_since(occs, nil)
      assert length(result) == 3
    end

    test "filters occurrences after sync point" do
      occs = [
        make_occurrence("ci.run.failed", "01JAAA"),
        make_occurrence("ci.run.passed", "01JBBB"),
        make_occurrence("vcs.commit", "01JCCC")
      ]

      result = Sync.occurrences_since(occs, "01JBBB")
      assert length(result) == 1
      assert hd(result).source.ulid == "01JCCC"
    end

    test "returns empty when all occurrences are before sync point" do
      occs = [
        make_occurrence("ci.run.failed", "01JAAA"),
        make_occurrence("ci.run.passed", "01JBBB")
      ]

      result = Sync.occurrences_since(occs, "01JZZZ")
      assert result == []
    end

    test "handles empty occurrence list" do
      assert Sync.occurrences_since([], nil) == []
      assert Sync.occurrences_since([], "01JAAA") == []
    end
  end

  describe "should_sync?/1" do
    test "syncs ci.run.failed" do
      assert Sync.should_sync?(make_occurrence("ci.run.failed", "01J001"))
    end

    test "syncs ci.run.passed" do
      assert Sync.should_sync?(make_occurrence("ci.run.passed", "01J001"))
    end

    test "syncs vcs.commit" do
      assert Sync.should_sync?(make_occurrence("vcs.commit", "01J001"))
    end

    test "syncs context.learning" do
      assert Sync.should_sync?(make_occurrence("context.learning", "01J001"))
    end

    test "syncs context.decision" do
      assert Sync.should_sync?(make_occurrence("context.decision", "01J001"))
    end

    test "does not sync context.pattern (derived)" do
      refute Sync.should_sync?(make_occurrence("context.pattern", "01J001"))
    end

    test "does not sync context.query (audit)" do
      refute Sync.should_sync?(make_occurrence("context.query", "01J001"))
    end

    test "does not sync unknown types" do
      refute Sync.should_sync?(make_occurrence("unknown.type", "01J001"))
    end
  end

  describe "filter_syncable/1" do
    test "filters out non-syncable occurrences" do
      occs = [
        make_occurrence("ci.run.failed", "01JAAA"),
        make_occurrence("context.pattern", "01JBBB"),
        make_occurrence("vcs.commit", "01JCCC"),
        make_occurrence("context.query", "01JDDD")
      ]

      result = Sync.filter_syncable(occs)
      types = Enum.map(result, & &1.type)
      assert types == ["ci.run.failed", "vcs.commit"]
    end
  end

  describe "update_sync_point/3" do
    test "sets sync point for a peer" do
      points = %{}
      updated = Sync.update_sync_point(points, "kerto@dev-b", "01JABC")
      assert updated == %{"kerto@dev-b" => "01JABC"}
    end

    test "updates existing sync point" do
      points = %{"kerto@dev-b" => "01JAAA"}
      updated = Sync.update_sync_point(points, "kerto@dev-b", "01JBBB")
      assert updated == %{"kerto@dev-b" => "01JBBB"}
    end

    test "preserves other peers" do
      points = %{"kerto@dev-b" => "01JAAA", "kerto@dev-c" => "01JBBB"}
      updated = Sync.update_sync_point(points, "kerto@dev-b", "01JCCC")
      assert updated["kerto@dev-b"] == "01JCCC"
      assert updated["kerto@dev-c"] == "01JBBB"
    end
  end

  describe "get_sync_point/2" do
    test "returns sync point for known peer" do
      points = %{"kerto@dev-b" => "01JABC"}
      assert Sync.get_sync_point(points, "kerto@dev-b") == "01JABC"
    end

    test "returns nil for unknown peer" do
      points = %{"kerto@dev-b" => "01JABC"}
      assert Sync.get_sync_point(points, "kerto@dev-c") == nil
    end
  end
end
