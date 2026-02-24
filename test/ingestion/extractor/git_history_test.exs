defmodule Kerto.Ingestion.Extractor.GitHistoryTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.GitHistory, Occurrence, Source}

  @source Source.new("kerto", "bootstrap", "01JABC")

  defp history_occurrence(commits) do
    Occurrence.new("bootstrap.git_history", %{commits: commits}, @source)
  end

  describe "extract/1" do
    test "creates file nodes for each file in commits" do
      occ = history_occurrence([%{files: ["auth.ex", "auth_test.exs"], message: "fix auth"}])
      ops = GitHistory.extract(occ)

      node_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_node end)
      names = Enum.map(node_ops, fn {:upsert_node, attrs} -> attrs.name end)
      assert "auth.ex" in names
      assert "auth_test.exs" in names
    end

    test "file nodes have kind :file and confidence 0.3" do
      occ = history_occurrence([%{files: ["auth.ex"], message: "m"}])
      ops = GitHistory.extract(occ)
      [{:upsert_node, attrs}] = Enum.filter(ops, fn {type, _} -> type == :upsert_node end)

      assert attrs.kind == :file
      assert_in_delta attrs.confidence, 0.3, 0.001
    end

    test "creates often_changes_with relationships for file pairs" do
      occ = history_occurrence([%{files: ["a.ex", "b.ex"], message: "m"}])
      ops = GitHistory.extract(occ)

      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert length(rel_ops) == 1

      [{:upsert_relationship, attrs}] = rel_ops
      assert attrs.source_name == "a.ex"
      assert attrs.target_name == "b.ex"
    end

    test "skips relationships when commit has more than 20 files" do
      files = Enum.map(1..21, &"file_#{&1}.ex")
      occ = history_occurrence([%{files: files, message: "big commit"}])
      ops = GitHistory.extract(occ)

      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert rel_ops == []

      node_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_node end)
      assert length(node_ops) == 21
    end

    test "relationships have confidence 0.3" do
      occ = history_occurrence([%{files: ["a.ex", "b.ex"], message: "m"}])
      ops = GitHistory.extract(occ)
      [rel | _] = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      {:upsert_relationship, attrs} = rel

      assert attrs.relation == :often_changes_with
      assert_in_delta attrs.confidence, 0.3, 0.001
    end

    test "handles multiple commits" do
      occ =
        history_occurrence([
          %{files: ["a.ex"], message: "first"},
          %{files: ["b.ex"], message: "second"}
        ])

      ops = GitHistory.extract(occ)
      node_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_node end)
      assert length(node_ops) == 2
    end

    test "empty commits list returns empty ops" do
      occ = history_occurrence([])
      assert GitHistory.extract(occ) == []
    end

    test "commits with empty files return no ops for that commit" do
      occ = history_occurrence([%{files: [], message: "empty"}])
      assert GitHistory.extract(occ) == []
    end

    test "evidence includes git history prefix and message" do
      occ = history_occurrence([%{files: ["a.ex", "b.ex"], message: "fix bug"}])
      ops = GitHistory.extract(occ)
      [rel | _] = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      {:upsert_relationship, attrs} = rel

      assert attrs.evidence == "git history: fix bug"
    end
  end
end
