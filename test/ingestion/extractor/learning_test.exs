defmodule Kerto.Ingestion.Extractor.LearningTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.Learning, Occurrence, Source}

  @source Source.new("agent", "dev", "01JABC")

  defp learning_occurrence(data) do
    Occurrence.new("context.learning", data, @source)
  end

  describe "extract/1" do
    test "creates subject and target nodes" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "auth.go",
          target_kind: :error,
          target_name: "OOM",
          relation: :caused_by,
          evidence: "auth.go OOM was caused by unbounded cache"
        })

      ops = Learning.extract(occ)
      nodes = for {:upsert_node, attrs} <- ops, do: {attrs.kind, attrs.name}

      assert {:file, "auth.go"} in nodes
      assert {:error, "OOM"} in nodes
    end

    test "creates relationship with specified relation" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "auth.go",
          target_kind: :concept,
          target_name: "caching",
          relation: :learned,
          evidence: "auth.go uses aggressive caching"
        })

      ops = Learning.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert rel.source_name == "auth.go"
      assert rel.target_name == "caching"
      assert rel.relation == :learned
    end

    test "default confidence is 0.8" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "a.go",
          target_kind: :pattern,
          target_name: "retry",
          relation: :learned,
          evidence: "uses retry"
        })

      ops = Learning.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.8, 0.001
    end

    test "uses provided confidence" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "a.go",
          target_kind: :pattern,
          target_name: "retry",
          relation: :learned,
          confidence: 0.95,
          evidence: "definitely uses retry"
        })

      ops = Learning.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.95, 0.001
    end

    test "evidence is preserved in relationship" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "a.go",
          target_kind: :error,
          target_name: "timeout",
          relation: :caused_by,
          evidence: "a.go timeout caused by slow DB"
        })

      ops = Learning.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence == "a.go timeout caused by slow DB"
    end

    test "node confidence matches relationship confidence" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "a.go",
          target_kind: :error,
          target_name: "timeout",
          relation: :caused_by,
          evidence: "test"
        })

      ops = Learning.extract(occ)
      nodes = for {:upsert_node, attrs} <- ops, do: attrs
      assert Enum.all?(nodes, &(&1.confidence == 0.8))
    end

    test "source and target kinds are preserved in relationship" do
      occ =
        learning_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :concept,
          target_name: "JWT",
          relation: :learned,
          evidence: "auth uses JWT"
        })

      ops = Learning.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.source_kind == :module
      assert rel.target_kind == :concept
    end

    test "returns exactly 2 nodes and 1 relationship" do
      occ =
        learning_occurrence(%{
          subject_kind: :file,
          subject_name: "a.go",
          target_kind: :error,
          target_name: "OOM",
          relation: :caused_by,
          evidence: "test"
        })

      ops = Learning.extract(occ)
      assert length(for {:upsert_node, _} <- ops, do: :ok) == 2
      assert length(for {:upsert_relationship, _} <- ops, do: :ok) == 1
    end
  end
end
