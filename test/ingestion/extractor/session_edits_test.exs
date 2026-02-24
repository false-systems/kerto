defmodule Kerto.Ingestion.Extractor.SessionEditsTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.SessionEdits, Occurrence, Source}

  @source Source.new("kerto", "agent", "01JABC")

  defp session_occurrence(files, agent \\ "claude-1") do
    Occurrence.new("agent.session_edits", %{files: files, agent: agent}, @source)
  end

  describe "extract/1" do
    test "creates file nodes at 0.6 confidence" do
      ops = SessionEdits.extract(session_occurrence(["auth.ex", "cache.ex"]))
      file_ops = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs

      assert length(file_ops) == 2
      assert Enum.all?(file_ops, &(&1.confidence == 0.6))
    end

    test "creates :edited_with relationships for 2+ files" do
      ops = SessionEdits.extract(session_occurrence(["auth.ex", "cache.ex"]))
      rel_ops = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert length(rel_ops) == 1
      [rel] = rel_ops
      assert rel.relation == :edited_with
      assert_in_delta rel.confidence, 0.5, 0.001
    end

    test "relationships are unidirectional (a < b only)" do
      ops = SessionEdits.extract(session_occurrence(["b.ex", "a.ex"]))
      rel_ops = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert length(rel_ops) == 1
      [rel] = rel_ops
      assert rel.source_name == "a.ex"
      assert rel.target_name == "b.ex"
    end

    test "no relationships for single file" do
      ops = SessionEdits.extract(session_occurrence(["auth.ex"]))
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert rel_ops == []
    end

    test "no relationships for more than 20 files" do
      files = for i <- 1..25, do: "file_#{String.pad_leading("#{i}", 2, "0")}.ex"
      ops = SessionEdits.extract(session_occurrence(files))
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert rel_ops == []
    end

    test "three files produce 3 unidirectional pairs" do
      ops = SessionEdits.extract(session_occurrence(["a.ex", "b.ex", "c.ex"]))
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert length(rel_ops) == 3
    end

    test "evidence includes agent name" do
      ops = SessionEdits.extract(session_occurrence(["a.ex", "b.ex"], "agent-42"))
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs
      assert rel.evidence =~ "agent-42"
    end

    test "empty files returns empty ops" do
      ops = SessionEdits.extract(session_occurrence([]))
      assert ops == []
    end
  end
end
