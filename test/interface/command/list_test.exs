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
      assert is_list(resp.data.nodes)
      assert length(resp.data.nodes) > 0
      names = Enum.map(resp.data.nodes, & &1.name)
      assert "auth.go" in names
    end

    test "node maps have expected fields" do
      resp = List.execute(@engine, %{})
      node = Enum.find(resp.data.nodes, &(&1.name == "auth.go"))
      assert node.kind == "file"
      assert is_float(node.relevance)
      assert is_integer(node.observations)
      assert is_binary(node.id)
      assert Map.has_key?(node, :pinned)
      assert Map.has_key?(node, :summary)
    end

    test "filters by kind" do
      resp = List.execute(@engine, %{kind: :module})
      assert resp.ok
      Enum.each(resp.data.nodes, fn n -> assert n.kind == "module" end)
    end

    test "filters by pinned" do
      Pin.execute(@engine, %{node: "auth.go", kind: :file})
      resp = List.execute(@engine, %{pinned: true})
      assert resp.ok
      names = Enum.map(resp.data.nodes, & &1.name)
      assert "auth.go" in names
      Enum.each(resp.data.nodes, fn n -> assert n.pinned == true end)
    end

    test "returns empty list for no matches" do
      resp = List.execute(@engine, %{kind: :decision})
      assert resp.ok
      assert resp.data.nodes == []
    end
  end

  describe "list relationships" do
    test "lists all relationships" do
      resp = List.execute(@engine, %{type: "relationships"})
      assert resp.ok
      assert is_list(resp.data.relationships)
      assert length(resp.data.relationships) > 0
    end

    test "relationship maps have expected fields" do
      resp = List.execute(@engine, %{type: "relationships"})
      rel = hd(resp.data.relationships)
      assert is_binary(rel.source)
      assert is_binary(rel.target)
      assert is_binary(rel.source_name)
      assert is_binary(rel.target_name)
      assert is_binary(rel.relation)
      assert is_float(rel.weight)
      assert is_integer(rel.observations)
      assert is_list(rel.evidence)
      assert Map.has_key?(rel, :pinned)
    end

    test "filters by relation type" do
      resp = List.execute(@engine, %{type: "rels", relation: :breaks})
      assert resp.ok
      Enum.each(resp.data.relationships, fn r -> assert r.relation == "breaks" end)
    end

    test "returns empty list for no matches" do
      resp = List.execute(@engine, %{type: "relationships", relation: :triggers})
      assert resp.ok
      assert resp.data.relationships == []
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
