defmodule Kerto.Engine.ApplierTest do
  use ExUnit.Case, async: true

  alias Kerto.Engine.Applier
  alias Kerto.Graph.{Graph, Identity}

  describe "apply_ops/3 with upsert_node" do
    test "creates a node in empty graph" do
      ops = [{:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}}]
      graph = Applier.apply_ops(Graph.new(), ops, "01JABC")
      assert Graph.node_count(graph) == 1

      id = Identity.compute_id(:file, "auth.go")
      assert {:ok, node} = Graph.get_node(graph, id)
      assert node.name == "auth.go"
      assert node.kind == :file
    end

    test "reinforces existing node" do
      ops = [{:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}}]
      graph = Applier.apply_ops(Graph.new(), ops, "01JAAA")
      graph = Applier.apply_ops(graph, ops, "01JBBB")

      assert Graph.node_count(graph) == 1
      id = Identity.compute_id(:file, "auth.go")
      {:ok, node} = Graph.get_node(graph, id)
      assert node.observations == 2
    end

    test "creates multiple nodes" do
      ops = [
        {:upsert_node, %{kind: :file, name: "a.go", confidence: 0.5}},
        {:upsert_node, %{kind: :file, name: "b.go", confidence: 0.5}},
        {:upsert_node, %{kind: :module, name: "test", confidence: 0.5}}
      ]

      graph = Applier.apply_ops(Graph.new(), ops, "01JABC")
      assert Graph.node_count(graph) == 3
    end
  end

  describe "apply_ops/3 with upsert_relationship" do
    test "creates relationship between nodes" do
      ops = [
        {:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}},
        {:upsert_node, %{kind: :module, name: "test", confidence: 0.7}},
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           confidence: 0.8,
           evidence: "CI failure"
         }}
      ]

      graph = Applier.apply_ops(Graph.new(), ops, "01JABC")
      assert Graph.node_count(graph) == 2
      assert Graph.relationship_count(graph) == 1
    end

    test "reinforces existing relationship" do
      ops = [
        {:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}},
        {:upsert_node, %{kind: :module, name: "test", confidence: 0.7}},
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           confidence: 0.8,
           evidence: "first failure"
         }}
      ]

      graph = Applier.apply_ops(Graph.new(), ops, "01JAAA")

      more_ops = [
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           confidence: 0.9,
           evidence: "second failure"
         }}
      ]

      graph = Applier.apply_ops(graph, more_ops, "01JBBB")
      assert Graph.relationship_count(graph) == 1

      src_id = Identity.compute_id(:file, "auth.go")
      tgt_id = Identity.compute_id(:module, "test")
      key = {src_id, :breaks, tgt_id}
      rel = graph.relationships[key]
      assert rel.observations == 2
      assert length(rel.evidence) == 2
    end
  end

  describe "apply_ops/3 with weaken_relationship" do
    test "weakens existing relationship" do
      ops = [
        {:upsert_node, %{kind: :file, name: "auth.go", confidence: 0.8}},
        {:upsert_node, %{kind: :module, name: "test", confidence: 0.7}},
        {:upsert_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           confidence: 0.8,
           evidence: "CI failure"
         }}
      ]

      graph = Applier.apply_ops(Graph.new(), ops, "01JABC")

      src_id = Identity.compute_id(:file, "auth.go")
      tgt_id = Identity.compute_id(:module, "test")
      original_weight = graph.relationships[{src_id, :breaks, tgt_id}].weight

      weaken_ops = [
        {:weaken_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           factor: 0.5
         }}
      ]

      graph = Applier.apply_ops(graph, weaken_ops, "01JDEF")
      new_weight = graph.relationships[{src_id, :breaks, tgt_id}].weight
      assert new_weight < original_weight
    end

    test "ignores weaken for nonexistent relationship" do
      graph = Graph.new()

      ops = [
        {:weaken_relationship,
         %{
           source_kind: :file,
           source_name: "auth.go",
           relation: :breaks,
           target_kind: :module,
           target_name: "test",
           factor: 0.5
         }}
      ]

      result = Applier.apply_ops(graph, ops, "01JABC")
      assert Graph.relationship_count(result) == 0
    end
  end

  describe "apply_ops/3 empty ops" do
    test "returns graph unchanged" do
      graph = Graph.new()
      assert Applier.apply_ops(graph, [], "01JABC") == graph
    end
  end

  describe "apply_ops/3 full extraction pipeline" do
    test "applies CI failure extraction ops end-to-end" do
      alias Kerto.Ingestion.{Extraction, Occurrence, Source}

      source = Source.new("sykli", "ci-agent", "01JABC")

      occurrence =
        Occurrence.new(
          "ci.run.failed",
          %{files: ["auth.go", "handler.go"], task: "test", message: "tests failed"},
          source
        )

      ops = Extraction.extract(occurrence)
      graph = Applier.apply_ops(Graph.new(), ops, "01JABC")

      assert Graph.node_count(graph) >= 2
      assert Graph.relationship_count(graph) >= 1
    end
  end
end
