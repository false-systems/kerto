defmodule Kerto.Ingestion.Extractor.SessionEndTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.SessionEnd, Occurrence, Source}

  @source Source.new("claude", "agent", "01JABC")

  defp session_occurrence(summary, files \\ []) do
    Occurrence.new("agent.session_end", %{summary: summary, files: files}, @source)
  end

  describe "extract/1" do
    test "creates file nodes for each file at confidence 0.7" do
      ops = SessionEnd.extract(session_occurrence("Fixed OOM", ["auth.go", "cache.go"]))
      file_ops = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs

      assert length(file_ops) == 2
      assert Enum.all?(file_ops, &(&1.confidence == 0.7))
      names = Enum.map(file_ops, & &1.name)
      assert "auth.go" in names
      assert "cache.go" in names
    end

    test "creates a concept node from slugified summary" do
      ops = SessionEnd.extract(session_occurrence("Fixed OOM in auth caused by cache", []))
      concept_ops = for {:upsert_node, %{kind: :concept} = attrs} <- ops, do: attrs

      assert [concept] = concept_ops
      assert concept.name == "fixed-oom-in-auth-caused-by-cache"
      assert_in_delta concept.confidence, 0.6, 0.001
    end

    test "slug truncates at 60 characters" do
      long_summary = String.duplicate("word ", 20)
      ops = SessionEnd.extract(session_occurrence(long_summary, []))
      [concept] = for {:upsert_node, %{kind: :concept} = attrs} <- ops, do: attrs

      assert String.length(concept.name) <= 60
    end

    test "creates learned relationships from each file to concept" do
      ops = SessionEnd.extract(session_occurrence("Fixed OOM", ["auth.go", "cache.go"]))
      rels = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert length(rels) == 2

      assert Enum.all?(rels, fn r ->
               r.relation == :learned and
                 r.source_kind == :file and
                 r.target_kind == :concept and
                 r.confidence == 0.6
             end)

      sources = Enum.map(rels, & &1.source_name)
      assert "auth.go" in sources
      assert "cache.go" in sources
    end

    test "relationship evidence is the full summary" do
      summary = "Fixed OOM in auth caused by unbounded cache"
      ops = SessionEnd.extract(session_occurrence(summary, ["auth.go"]))
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence == summary
    end

    test "no files produces concept node only" do
      ops = SessionEnd.extract(session_occurrence("Just exploring", []))
      assert length(ops) == 1
      assert [{:upsert_node, %{kind: :concept}}] = ops
    end

    test "slug handles special characters" do
      ops = SessionEnd.extract(session_occurrence("Fix auth.go's OOM — cache issue!", []))
      [concept] = for {:upsert_node, %{kind: :concept} = attrs} <- ops, do: attrs
      refute concept.name =~ " "
      refute concept.name =~ "!"
    end
  end
end
