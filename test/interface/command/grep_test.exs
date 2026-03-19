defmodule Kerto.Interface.Command.GrepTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Grep
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_grep_engine

  setup do
    start_supervised!({Kerto.Engine, name: @engine, decay_interval_ms: :timer.hours(1)})

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go", "session.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(@engine, occ)
    :ok
  end

  describe "node search (default)" do
    test "finds nodes matching pattern" do
      resp = Grep.execute(@engine, %{pattern: "auth"})
      assert resp.ok
      assert is_list(resp.data.nodes)
      names = Enum.map(resp.data.nodes, & &1.name)
      assert "auth.go" in names
    end

    test "returns empty list for no matches" do
      resp = Grep.execute(@engine, %{pattern: "zzzzz"})
      assert resp.ok
      assert resp.data.nodes == []
    end

    test "filters by kind" do
      resp = Grep.execute(@engine, %{pattern: "auth", kind: :module})
      assert resp.ok
      # auth.go is a :file node, not :module — but the CI failure extractor
      # may create module nodes too. Check that all results match the kind.
      Enum.each(resp.data.nodes, fn n -> assert n.kind == "module" end)
    end

    test "returns error when pattern is missing" do
      resp = Grep.execute(@engine, %{})
      refute resp.ok
      assert resp.error =~ "pattern"
    end
  end

  describe "relationship search" do
    test "finds relationships by evidence" do
      resp = Grep.execute(@engine, %{pattern: "CI", evidence: true})
      assert resp.ok
      assert is_list(resp.data.relationships)
    end

    test "filters by relation type" do
      resp = Grep.execute(@engine, %{pattern: "CI", evidence: true, relation: :breaks})
      assert resp.ok
      Enum.each(resp.data.relationships, fn r -> assert r.relation == "breaks" end)
    end

    test "returns empty list for no evidence matches" do
      resp = Grep.execute(@engine, %{pattern: "zzzzz", evidence: true})
      assert resp.ok
      assert resp.data.relationships == []
    end
  end

  describe "relationship search by type flag" do
    test "searches relationships via type=rels" do
      resp = Grep.execute(@engine, %{pattern: "breaks", type: "rels"})
      assert resp.ok
      assert Map.has_key?(resp.data, :relationships)
    end
  end
end
