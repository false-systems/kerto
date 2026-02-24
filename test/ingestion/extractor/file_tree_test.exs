defmodule Kerto.Ingestion.Extractor.FileTreeTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.FileTree, Occurrence, Source}

  @source Source.new("kerto", "bootstrap", "01JABC")

  defp tree_occurrence(files) do
    Occurrence.new("bootstrap.file_tree", %{files: files}, @source)
  end

  describe "extract/1" do
    test "creates file nodes at 0.2 confidence" do
      occ = tree_occurrence(["lib/auth.ex", "lib/token.ex"])
      ops = FileTree.extract(occ)

      node_ops =
        Enum.filter(ops, fn
          {:upsert_node, %{kind: :file}} -> true
          _ -> false
        end)

      assert length(node_ops) == 2

      Enum.each(node_ops, fn {:upsert_node, attrs} ->
        assert attrs.kind == :file
        assert_in_delta attrs.confidence, 0.2, 0.001
      end)
    end

    test "creates directory module nodes" do
      occ = tree_occurrence(["lib/auth.ex"])
      ops = FileTree.extract(occ)

      dir_ops =
        Enum.filter(ops, fn
          {:upsert_node, %{kind: :module}} -> true
          _ -> false
        end)

      assert length(dir_ops) == 1
      [{:upsert_node, attrs}] = dir_ops
      assert attrs.name == "lib"
    end

    test "creates :part_of relationships from files to directories" do
      occ = tree_occurrence(["lib/auth.ex"])
      ops = FileTree.extract(occ)

      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert length(rel_ops) == 1

      [{:upsert_relationship, attrs}] = rel_ops
      assert attrs.source_kind == :file
      assert attrs.source_name == "lib/auth.ex"
      assert attrs.relation == :part_of
      assert attrs.target_kind == :module
      assert attrs.target_name == "lib"
      assert attrs.evidence == "file tree"
    end

    test "handles nested directories" do
      occ = tree_occurrence(["lib/auth/token.ex"])
      ops = FileTree.extract(occ)

      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      [{:upsert_relationship, attrs}] = rel_ops
      assert attrs.target_name == "lib/auth"
    end

    test "deduplicates directory nodes" do
      occ = tree_occurrence(["lib/a.ex", "lib/b.ex"])
      ops = FileTree.extract(occ)

      dir_ops =
        Enum.filter(ops, fn
          {:upsert_node, %{kind: :module}} -> true
          _ -> false
        end)

      assert length(dir_ops) == 1
    end

    test "root-level files get no :part_of relationship" do
      occ = tree_occurrence(["README.md"])
      ops = FileTree.extract(occ)

      rel_ops = Enum.filter(ops, fn {type, _} -> type == :upsert_relationship end)
      assert rel_ops == []
    end

    test "empty files list returns empty ops" do
      occ = tree_occurrence([])
      assert FileTree.extract(occ) == []
    end
  end
end
