defmodule Kerto.Ingestion.Extractor.ApproachAbandonedTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.ApproachAbandoned, Occurrence, Source}

  @source Source.new("claude", "agent", "01JABC")

  defp abandoned_occurrence(data) do
    Occurrence.new("agent.approach_abandoned", data, @source)
  end

  describe "extract/1" do
    test "creates subject node, approach node, and tried_failed relationship" do
      occ =
        abandoned_occurrence(%{
          subject: "auth.go",
          approach: "redis caching",
          reason: "too complex"
        })

      ops = ApproachAbandoned.extract(occ)

      node_ops = for {:upsert_node, attrs} <- ops, do: attrs
      rel_ops = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert length(node_ops) == 2
      assert length(rel_ops) == 1

      [rel] = rel_ops
      assert rel.relation == :tried_failed
      assert rel.source_name == "auth.go"
      assert rel.target_name == "redis caching"
      assert rel.evidence == "too complex"
    end

    test "defaults subject_kind to :file and approach_kind to :pattern" do
      occ = abandoned_occurrence(%{subject: "auth.go", approach: "caching"})
      ops = ApproachAbandoned.extract(occ)

      node_ops = for {:upsert_node, attrs} <- ops, do: attrs
      kinds = Enum.map(node_ops, & &1.kind)
      assert :file in kinds
      assert :pattern in kinds
    end

    test "uses custom kinds when provided" do
      occ =
        abandoned_occurrence(%{
          subject: "auth",
          subject_kind: :module,
          approach: "jwt tokens",
          approach_kind: :concept
        })

      ops = ApproachAbandoned.extract(occ)
      node_ops = for {:upsert_node, attrs} <- ops, do: attrs
      kinds = Enum.map(node_ops, & &1.kind)
      assert :module in kinds
      assert :concept in kinds
    end

    test "default confidence is 0.7" do
      occ = abandoned_occurrence(%{subject: "auth.go", approach: "caching"})
      [{:upsert_node, attrs} | _] = ApproachAbandoned.extract(occ)
      assert_in_delta attrs.confidence, 0.7, 0.001
    end

    test "returns empty ops when subject is missing" do
      occ = abandoned_occurrence(%{approach: "caching"})
      assert ApproachAbandoned.extract(occ) == []
    end

    test "returns empty ops when approach is missing" do
      occ = abandoned_occurrence(%{subject: "auth.go"})
      assert ApproachAbandoned.extract(occ) == []
    end

    test "returns empty ops when subject is empty" do
      occ = abandoned_occurrence(%{subject: "", approach: "caching"})
      assert ApproachAbandoned.extract(occ) == []
    end

    test "default reason is 'approach abandoned'" do
      occ = abandoned_occurrence(%{subject: "auth.go", approach: "caching"})
      [_, _, {:upsert_relationship, attrs}] = ApproachAbandoned.extract(occ)
      assert attrs.evidence == "approach abandoned"
    end
  end
end
