defmodule Kerto.Ingestion.Extractor.FileReadTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.FileRead, Occurrence, Source}

  @source Source.new("claude", "agent", "01JABC")

  defp read_occurrence(file) do
    Occurrence.new("agent.file_read", %{file: file}, @source)
  end

  describe "extract/1" do
    test "creates a single file node" do
      ops = FileRead.extract(read_occurrence("lib/foo.ex"))
      assert [{:upsert_node, attrs}] = ops
      assert attrs.kind == :file
      assert attrs.name == "lib/foo.ex"
    end

    test "confidence is 0.1 (very weak — just a read)" do
      [{:upsert_node, attrs}] = FileRead.extract(read_occurrence("lib/foo.ex"))
      assert_in_delta attrs.confidence, 0.1, 0.001
    end

    test "produces no relationships" do
      ops = FileRead.extract(read_occurrence("lib/foo.ex"))
      rel_ops = for {:upsert_relationship, _} <- ops, do: :ok
      assert rel_ops == []
    end

    test "returns empty ops when file key is missing" do
      occ = Occurrence.new("agent.file_read", %{}, @source)
      assert FileRead.extract(occ) == []
    end

    test "returns empty ops when file is empty string" do
      occ = Occurrence.new("agent.file_read", %{file: ""}, @source)
      assert FileRead.extract(occ) == []
    end
  end
end
