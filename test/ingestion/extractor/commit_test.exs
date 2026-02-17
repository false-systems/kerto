defmodule Kerto.Ingestion.Extractor.CommitTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.Commit, Occurrence, Source}

  @source Source.new("github", "vcs-agent", "01JABC")

  defp commit_occurrence(files) do
    Occurrence.new("vcs.commit", %{files: files, message: "fix auth"}, @source)
  end

  describe "extract/1" do
    test "creates file nodes for each file" do
      ops = Commit.extract(commit_occurrence(["auth.go", "auth_test.go"]))

      node_ops =
        Enum.filter(ops, fn {type, _} -> type == :upsert_node end)

      names = Enum.map(node_ops, fn {:upsert_node, attrs} -> attrs.name end)
      assert "auth.go" in names
      assert "auth_test.go" in names
    end

    test "file nodes have kind :file and confidence 0.5" do
      ops = Commit.extract(commit_occurrence(["auth.go"]))
      [{:upsert_node, attrs}] = Enum.filter(ops, fn {type, _} -> type == :upsert_node end)

      assert attrs.kind == :file
      assert_in_delta attrs.confidence, 0.5, 0.001
    end

    test "creates bidirectional often_changes_with relationships" do
      ops = Commit.extract(commit_occurrence(["a.go", "b.go"]))

      rel_ops =
        Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)

      pairs =
        Enum.map(rel_ops, fn {:upsert_relationship, attrs} ->
          {attrs.source_name, attrs.target_name}
        end)

      assert {"a.go", "b.go"} in pairs
      assert {"b.go", "a.go"} in pairs
    end

    test "relationships have correct relation and confidence" do
      ops = Commit.extract(commit_occurrence(["a.go", "b.go"]))
      [rel | _] = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      {:upsert_relationship, attrs} = rel

      assert attrs.relation == :often_changes_with
      assert_in_delta attrs.confidence, 0.5, 0.001
    end

    test "single file produces no relationships" do
      ops = Commit.extract(commit_occurrence(["auth.go"]))
      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert rel_ops == []
    end

    test "three files produce 6 bidirectional pairs" do
      ops = Commit.extract(commit_occurrence(["a.go", "b.go", "c.go"]))
      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert length(rel_ops) == 6
    end

    test "empty files list returns empty ops" do
      ops = Commit.extract(commit_occurrence([]))
      assert ops == []
    end

    test "evidence includes commit message" do
      ops = Commit.extract(commit_occurrence(["a.go", "b.go"]))
      [rel | _] = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      {:upsert_relationship, attrs} = rel

      assert attrs.evidence =~ "fix auth"
    end
  end
end
