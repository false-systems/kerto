defmodule Kerto.Ingestion.Extractor.DecisionTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.Decision, Occurrence, Source}

  @source Source.new("agent", "architect", "01JABC")

  defp decision_occurrence(data) do
    Occurrence.new("context.decision", data, @source)
  end

  describe "extract/1" do
    test "creates subject and target nodes" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "Use JWT over sessions — stateless requirement"
        })

      ops = Decision.extract(occ)
      nodes = for {:upsert_node, attrs} <- ops, do: {attrs.kind, attrs.name}

      assert {:module, "auth"} in nodes
      assert {:decision, "JWT"} in nodes
    end

    test "creates :decided relationship" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "stateless auth"
        })

      ops = Decision.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.relation == :decided
    end

    test "default confidence is 0.9" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "test"
        })

      ops = Decision.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.9, 0.001
    end

    test "uses provided confidence" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          confidence: 1.0,
          evidence: "absolutely certain"
        })

      ops = Decision.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 1.0, 0.001
    end

    test "evidence is preserved" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "Use JWT — stateless requirement"
        })

      ops = Decision.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence == "Use JWT — stateless requirement"
    end

    test "source and target kinds flow through" do
      occ =
        decision_occurrence(%{
          subject_kind: :file,
          subject_name: "config.yaml",
          target_kind: :concept,
          target_name: "microservices",
          evidence: "chose microservices"
        })

      ops = Decision.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.source_kind == :file
      assert rel.target_kind == :concept
    end

    test "returns exactly 2 nodes and 1 relationship" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "test"
        })

      ops = Decision.extract(occ)
      assert length(for {:upsert_node, _} <- ops, do: :ok) == 2
      assert length(for {:upsert_relationship, _} <- ops, do: :ok) == 1
    end

    test "node confidence matches relationship confidence" do
      occ =
        decision_occurrence(%{
          subject_kind: :module,
          subject_name: "auth",
          target_kind: :decision,
          target_name: "JWT",
          evidence: "test"
        })

      ops = Decision.extract(occ)
      nodes = for {:upsert_node, attrs} <- ops, do: attrs
      assert Enum.all?(nodes, &(&1.confidence == 0.9))
    end
  end
end
