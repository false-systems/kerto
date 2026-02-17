defmodule Kerto.Ingestion.Extractor.CiFailureTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.CiFailure, Occurrence, Source}

  @source Source.new("github-actions", "ci-bot", "01JABC")

  defp failure_occurrence(data) do
    Occurrence.new("ci.run.failed", data, @source)
  end

  describe "extract/1" do
    test "creates file nodes for changed files" do
      occ = failure_occurrence(%{files: ["auth.go", "handler.go"], task: "test"})
      ops = CiFailure.extract(occ)
      file_nodes = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs.name
      assert "auth.go" in file_nodes
      assert "handler.go" in file_nodes
    end

    test "creates module node for the failed task" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiFailure.extract(occ)
      module_nodes = for {:upsert_node, %{kind: :module} = attrs} <- ops, do: attrs.name
      assert "test" in module_nodes
    end

    test "creates :breaks relationship from file to task" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiFailure.extract(occ)

      breaks =
        for {:upsert_relationship, %{relation: :breaks} = attrs} <- ops,
            do: {attrs.source_name, attrs.target_name}

      assert {"auth.go", "test"} in breaks
    end

    test "default confidence is 0.7" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiFailure.extract(occ)
      [rel | _] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.7, 0.001
    end

    test "uses provided confidence when available" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test", confidence: 0.95})
      ops = CiFailure.extract(occ)
      [rel | _] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.95, 0.001
    end

    test "multiple files create multiple :breaks relationships" do
      occ = failure_occurrence(%{files: ["a.go", "b.go", "c.go"], task: "lint"})
      ops = CiFailure.extract(occ)
      breaks = for {:upsert_relationship, %{relation: :breaks}} <- ops, do: :ok
      assert length(breaks) == 3
    end

    test "evidence includes task name" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test", error: "exit 1"})
      ops = CiFailure.extract(occ)
      [rel | _] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence =~ "test"
    end

    test "evidence includes error when present" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test", error: "nil pointer"})
      ops = CiFailure.extract(occ)
      [rel | _] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence =~ "nil pointer"
    end

    test "empty files returns only module node" do
      occ = failure_occurrence(%{files: [], task: "test"})
      ops = CiFailure.extract(occ)
      node_ops = for {:upsert_node, attrs} <- ops, do: attrs
      assert length(node_ops) == 1
      assert hd(node_ops).kind == :module
    end

    test "file nodes have confidence 0.7" do
      occ = failure_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiFailure.extract(occ)
      [file_node] = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs
      assert_in_delta file_node.confidence, 0.7, 0.001
    end
  end
end
