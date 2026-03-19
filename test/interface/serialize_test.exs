defmodule Kerto.Interface.SerializeTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.Serialize
  alias Kerto.Graph.{Node, Relationship, Identity}

  describe "node_to_map/1" do
    test "converts all node fields" do
      node = Node.new(:file, "auth.go", "01JABC")
      map = Serialize.node_to_map(node)

      assert map.id == node.id
      assert map.name == "auth.go"
      assert map.kind == "file"
      assert map.relevance == node.relevance
      assert map.observations == 1
      assert map.first_seen == "01JABC"
      assert map.last_seen == "01JABC"
      assert map.pinned == false
      assert map.summary == nil
    end

    test "includes summary when present" do
      node = %{Node.new(:file, "auth.go", "01JABC") | summary: "handles auth"}
      map = Serialize.node_to_map(node)
      assert map.summary == "handles auth"
    end

    test "includes pinned status" do
      node = %{Node.new(:file, "auth.go", "01JABC") | pinned: true}
      map = Serialize.node_to_map(node)
      assert map.pinned == true
    end
  end

  describe "rel_to_map/2" do
    test "converts all relationship fields with name lookup" do
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "test.go")
      rel = Relationship.new(source_id, :breaks, target_id, "01JABC", "CI failed")

      lookup = %{
        source_id => Node.new(:file, "auth.go", "01JABC"),
        target_id => Node.new(:file, "test.go", "01JABC")
      }

      map = Serialize.rel_to_map(rel, lookup)

      assert map.source == source_id
      assert map.target == target_id
      assert map.source_name == "auth.go"
      assert map.target_name == "test.go"
      assert map.relation == "breaks"
      assert map.weight == 0.5
      assert map.observations == 1
      assert map.evidence == ["CI failed"]
      assert map.pinned == false
    end

    test "falls back to id when name not in lookup" do
      source_id = Identity.compute_id(:file, "auth.go")
      target_id = Identity.compute_id(:file, "test.go")
      rel = Relationship.new(source_id, :breaks, target_id, "01JABC", "CI failed")

      map = Serialize.rel_to_map(rel, %{})

      assert map.source_name == source_id
      assert map.target_name == target_id
    end

    test "includes pinned status" do
      source_id = Identity.compute_id(:file, "a.go")
      target_id = Identity.compute_id(:file, "b.go")
      rel = %{Relationship.new(source_id, :breaks, target_id, "01JABC", "e") | pinned: true}

      map = Serialize.rel_to_map(rel, %{})
      assert map.pinned == true
    end
  end

  describe "to_json_safe/1" do
    test "converts atoms to strings" do
      assert Serialize.to_json_safe(:file) == "file"
    end

    test "passes strings through" do
      assert Serialize.to_json_safe("hello") == "hello"
    end

    test "passes numbers through" do
      assert Serialize.to_json_safe(42) == 42
      assert Serialize.to_json_safe(3.14) == 3.14
    end

    test "passes booleans through" do
      assert Serialize.to_json_safe(true) == true
      assert Serialize.to_json_safe(false) == false
    end

    test "passes nil through" do
      assert Serialize.to_json_safe(nil) == nil
    end

    test "converts map keys and values recursively" do
      input = %{kind: :file, name: "auth.go", count: 1}
      result = Serialize.to_json_safe(input)

      assert result == %{"kind" => "file", "name" => "auth.go", "count" => 1}
    end

    test "converts lists recursively" do
      input = [:file, :module]
      assert Serialize.to_json_safe(input) == ["file", "module"]
    end

    test "handles nested structures" do
      input = %{nodes: [%{kind: :file, name: "a.go"}]}
      result = Serialize.to_json_safe(input)
      assert result == %{"nodes" => [%{"kind" => "file", "name" => "a.go"}]}
    end
  end
end
