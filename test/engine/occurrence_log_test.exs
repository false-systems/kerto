defmodule Kerto.Engine.OccurrenceLogTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.OccurrenceLog
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new("ci.run.failed", %{files: ["a.go"], task: "test"}, source)
  end

  setup do
    log = start_supervised!({OccurrenceLog, max: 5, name: :test_occ_log})
    %{log: log}
  end

  describe "append/2 and all/1" do
    test "stores an occurrence", %{log: log} do
      occ = make_occurrence("01JAAA")
      assert :ok = OccurrenceLog.append(log, occ)
      assert [^occ] = OccurrenceLog.all(log)
    end

    test "stores multiple occurrences in order", %{log: log} do
      occ1 = make_occurrence("01JAAA")
      occ2 = make_occurrence("01JBBB")
      occ3 = make_occurrence("01JCCC")

      OccurrenceLog.append(log, occ1)
      OccurrenceLog.append(log, occ2)
      OccurrenceLog.append(log, occ3)

      result = OccurrenceLog.all(log)
      ulids = Enum.map(result, & &1.source.ulid)
      assert ulids == ["01JAAA", "01JBBB", "01JCCC"]
    end
  end

  describe "ring buffer eviction" do
    test "evicts oldest when at capacity", %{log: log} do
      for i <- 1..6 do
        ulid = String.pad_leading("#{i}", 6, "0")
        OccurrenceLog.append(log, make_occurrence(ulid))
      end

      result = OccurrenceLog.all(log)
      assert length(result) == 5
      # oldest (000001) should be evicted
      ulids = Enum.map(result, & &1.source.ulid)
      refute "000001" in ulids
      assert "000006" in ulids
    end
  end

  describe "since/2" do
    test "returns all occurrences when sync_point is nil", %{log: log} do
      OccurrenceLog.append(log, make_occurrence("01JAAA"))
      OccurrenceLog.append(log, make_occurrence("01JBBB"))

      result = OccurrenceLog.since(log, nil)
      assert length(result) == 2
    end

    test "returns occurrences after sync point", %{log: log} do
      OccurrenceLog.append(log, make_occurrence("01JAAA"))
      OccurrenceLog.append(log, make_occurrence("01JBBB"))
      OccurrenceLog.append(log, make_occurrence("01JCCC"))

      result = OccurrenceLog.since(log, "01JBBB")
      assert length(result) == 1
      assert hd(result).source.ulid == "01JCCC"
    end

    test "returns empty when all before sync point", %{log: log} do
      OccurrenceLog.append(log, make_occurrence("01JAAA"))
      OccurrenceLog.append(log, make_occurrence("01JBBB"))

      assert OccurrenceLog.since(log, "01JZZZ") == []
    end

    test "returns empty for empty log", %{log: log} do
      assert OccurrenceLog.since(log, nil) == []
      assert OccurrenceLog.since(log, "01JAAA") == []
    end
  end

  describe "count/1" do
    test "returns 0 for empty log", %{log: log} do
      assert OccurrenceLog.count(log) == 0
    end

    test "returns count after appends", %{log: log} do
      OccurrenceLog.append(log, make_occurrence("01JAAA"))
      OccurrenceLog.append(log, make_occurrence("01JBBB"))
      assert OccurrenceLog.count(log) == 2
    end
  end
end
