defmodule Kerto.Ingestion.OccurrenceTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Occurrence, Source}

  @source Source.new("github-actions", "ci-bot", "01JABC")

  describe "new/3" do
    test "creates occurrence with type and data" do
      occ = Occurrence.new("ci.run.failed", %{task: "test", files: ["auth.go"]}, @source)
      assert occ.type == "ci.run.failed"
      assert occ.data.task == "test"
      assert occ.source == @source
    end

    test "enforces string type" do
      assert_raise FunctionClauseError, fn ->
        Occurrence.new(:ci_failure, %{}, @source)
      end
    end

    test "enforces map data" do
      assert_raise FunctionClauseError, fn ->
        Occurrence.new("ci.run.failed", "not a map", @source)
      end
    end

    test "enforces Source struct" do
      assert_raise FunctionClauseError, fn ->
        Occurrence.new("ci.run.failed", %{}, %{system: "x"})
      end
    end

    test "preserves all data fields" do
      data = %{task: "lint", files: ["a.go", "b.go"], exit_code: 1}
      occ = Occurrence.new("ci.run.failed", data, @source)
      assert occ.data == data
    end

    test "ulid comes from source" do
      occ = Occurrence.new("vcs.commit", %{}, @source)
      assert occ.source.ulid == "01JABC"
    end
  end

  describe "struct" do
    test "enforces all keys" do
      assert_raise ArgumentError, fn ->
        struct!(Occurrence, type: "x", data: %{})
      end
    end

    test "is a proper struct" do
      occ = Occurrence.new("vcs.commit", %{}, @source)
      assert %Occurrence{} = occ
    end
  end
end
