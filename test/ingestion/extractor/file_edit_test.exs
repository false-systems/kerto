defmodule Kerto.Ingestion.Extractor.FileEditTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.FileEdit, Occurrence, Source}

  @source Source.new("claude", "agent", "01JABC")

  defp edit_occurrence(file, tool \\ "Edit") do
    Occurrence.new("agent.file_edit", %{file: file, tool: tool}, @source)
  end

  describe "extract/1" do
    test "creates a single file node" do
      ops = FileEdit.extract(edit_occurrence("lib/foo.ex"))
      assert [{:upsert_node, attrs}] = ops
      assert attrs.kind == :file
      assert attrs.name == "lib/foo.ex"
    end

    test "confidence is 0.4 (weak — single edit)" do
      [{:upsert_node, attrs}] = FileEdit.extract(edit_occurrence("lib/foo.ex"))
      assert_in_delta attrs.confidence, 0.4, 0.001
    end

    test "produces no relationships" do
      ops = FileEdit.extract(edit_occurrence("lib/foo.ex"))
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert rel_ops == []
    end

    test "works with Write tool" do
      [{:upsert_node, attrs}] = FileEdit.extract(edit_occurrence("lib/bar.ex", "Write"))
      assert attrs.name == "lib/bar.ex"
    end

    test "works with MultiEdit tool" do
      [{:upsert_node, attrs}] = FileEdit.extract(edit_occurrence("lib/baz.ex", "MultiEdit"))
      assert attrs.name == "lib/baz.ex"
    end
  end
end
