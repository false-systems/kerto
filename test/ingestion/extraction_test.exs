defmodule Kerto.Ingestion.ExtractionTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extraction, Occurrence, Source}

  @source Source.new("system", "agent", "01JABC")

  describe "extract/1" do
    test "dispatches vcs.commit to Commit extractor" do
      occ = Occurrence.new("vcs.commit", %{files: ["a.go", "b.go"], message: "fix"}, @source)
      ops = Extraction.extract(occ)

      assert length(ops) > 0
      node_ops = for {:upsert_node, _} <- ops, do: :ok
      assert length(node_ops) == 2
    end

    test "dispatches ci.run.failed to CiFailure extractor" do
      occ = Occurrence.new("ci.run.failed", %{files: ["auth.go"], task: "test"}, @source)
      ops = Extraction.extract(occ)

      breaks = for {:upsert_relationship, %{relation: :breaks}} <- ops, do: :ok
      assert length(breaks) == 1
    end

    test "dispatches ci.run.passed to CiSuccess extractor" do
      occ = Occurrence.new("ci.run.passed", %{files: ["auth.go"], task: "test"}, @source)
      ops = Extraction.extract(occ)

      weakens = for {:weaken_relationship, _} <- ops, do: :ok
      assert length(weakens) == 1
    end

    test "dispatches context.learning to Learning extractor" do
      occ =
        Occurrence.new(
          "context.learning",
          %{
            subject_kind: :file,
            subject_name: "a.go",
            target_kind: :error,
            target_name: "OOM",
            relation: :caused_by,
            evidence: "caused by cache"
          },
          @source
        )

      ops = Extraction.extract(occ)
      rels = for {:upsert_relationship, %{relation: :caused_by}} <- ops, do: :ok
      assert length(rels) == 1
    end

    test "dispatches context.decision to Decision extractor" do
      occ =
        Occurrence.new(
          "context.decision",
          %{
            subject_kind: :module,
            subject_name: "auth",
            target_kind: :decision,
            target_name: "JWT",
            evidence: "stateless"
          },
          @source
        )

      ops = Extraction.extract(occ)
      rels = for {:upsert_relationship, %{relation: :decided}} <- ops, do: :ok
      assert length(rels) == 1
    end

    test "returns empty list for unknown type" do
      occ = Occurrence.new("unknown.type", %{}, @source)
      assert Extraction.extract(occ) == []
    end

    test "returns empty list for nil-like types" do
      occ = Occurrence.new("", %{}, @source)
      assert Extraction.extract(occ) == []
    end

    test "commit with multiple files produces relationship pairs" do
      occ =
        Occurrence.new("vcs.commit", %{files: ["a.go", "b.go", "c.go"], message: "big"}, @source)

      ops = Extraction.extract(occ)
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert length(rel_ops) == 6
    end

    test "ci failure with confidence passes through" do
      occ =
        Occurrence.new(
          "ci.run.failed",
          %{files: ["x.go"], task: "lint", confidence: 0.95},
          @source
        )

      ops = Extraction.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.95, 0.001
    end

    test "result is always a flat list of ops" do
      occ =
        Occurrence.new("ci.run.failed", %{files: ["a.go", "b.go"], task: "test"}, @source)

      ops = Extraction.extract(occ)
      assert is_list(ops)

      assert Enum.all?(ops, fn {type, _} ->
               type in [:upsert_node, :upsert_relationship, :weaken_relationship]
             end)
    end

    test "learning with custom confidence passes through" do
      occ =
        Occurrence.new(
          "context.learning",
          %{
            subject_kind: :file,
            subject_name: "a.go",
            target_kind: :pattern,
            target_name: "retry",
            relation: :learned,
            confidence: 0.6,
            evidence: "maybe retry"
          },
          @source
        )

      ops = Extraction.extract(occ)
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert_in_delta rel.confidence, 0.6, 0.001
    end

    test "decision creates :decided relationship type" do
      occ =
        Occurrence.new(
          "context.decision",
          %{
            subject_kind: :module,
            subject_name: "api",
            target_kind: :decision,
            target_name: "REST",
            evidence: "chose REST"
          },
          @source
        )

      ops = Extraction.extract(occ)
      rels = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert hd(rels).relation == :decided
    end
  end
end
