defmodule Kerto.Interface.Command.ListTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.{List, Pin}
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_list_engine

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

  describe "list nodes" do
    test "lists all nodes by default" do
      resp = List.execute(@engine, %{})
      assert resp.ok
      assert resp.data =~ "node(s)"
      assert resp.data =~ "auth.go"
    end

    test "filters by kind" do
      resp = List.execute(@engine, %{kind: :module})
      assert resp.ok
      assert resp.data =~ "module:"
    end

    test "filters by pinned" do
      Pin.execute(@engine, %{node: "auth.go", kind: :file})
      resp = List.execute(@engine, %{pinned: true})
      assert resp.ok
      assert resp.data =~ "auth.go"
      assert resp.data =~ "[pinned]"
    end

    test "returns message for empty result" do
      resp = List.execute(@engine, %{kind: :decision})
      assert resp.ok
      assert resp.data =~ "No nodes found"
    end
  end

  describe "list relationships" do
    test "lists all relationships" do
      resp = List.execute(@engine, %{type: "relationships"})
      assert resp.ok
      assert resp.data =~ "relationship(s)"
    end

    test "filters by relation type" do
      resp = List.execute(@engine, %{type: "rels", relation: :breaks})
      assert resp.ok
      assert resp.data =~ "breaks"
    end

    test "returns message for empty result" do
      resp = List.execute(@engine, %{type: "relationships", relation: :triggers})
      assert resp.ok
      assert resp.data =~ "No relationships found"
    end
  end

  describe "invalid type" do
    test "returns error for unknown type" do
      resp = List.execute(@engine, %{type: "bananas"})
      refute resp.ok
      assert resp.error =~ "unknown list type"
    end
  end
end
