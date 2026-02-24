defmodule Kerto.Ingestion.Extractor.ToolErrorTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.ToolError, Occurrence, Source}

  @source Source.new("claude", "agent", "01JABC")

  defp error_occurrence(error, opts \\ []) do
    tool = Keyword.get(opts, :tool, "Bash")
    files = Keyword.get(opts, :files, [])
    Occurrence.new("agent.tool_error", %{error: error, tool: tool, files: files}, @source)
  end

  describe "extract/1" do
    test "creates an error node from error text" do
      ops = ToolError.extract(error_occurrence("connection refused"))
      error_ops = for {:upsert_node, %{kind: :error} = attrs} <- ops, do: attrs

      assert [error_node] = error_ops
      assert error_node.name == "connection-refused"
      assert_in_delta error_node.confidence, 0.6, 0.001
    end

    test "slugifies error text" do
      ops = ToolError.extract(error_occurrence("OOM: killed process 1234!"))
      [error_node] = for {:upsert_node, %{kind: :error} = attrs} <- ops, do: attrs

      refute error_node.name =~ " "
      refute error_node.name =~ "!"
      refute error_node.name =~ ":"
    end

    test "truncates slug at 60 characters" do
      long_error = String.duplicate("error word ", 20)
      ops = ToolError.extract(error_occurrence(long_error))
      [error_node] = for {:upsert_node, %{kind: :error} = attrs} <- ops, do: attrs

      assert String.length(error_node.name) <= 60
    end

    test "creates file nodes when files are provided" do
      ops = ToolError.extract(error_occurrence("fail", files: ["auth.ex", "cache.ex"]))
      file_ops = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs

      assert length(file_ops) == 2
      names = Enum.map(file_ops, & &1.name)
      assert "auth.ex" in names
      assert "cache.ex" in names
    end

    test "creates caused_by relationships from files to error" do
      ops = ToolError.extract(error_occurrence("fail", files: ["auth.ex"]))
      rel_ops = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert [rel] = rel_ops
      assert rel.source_kind == :file
      assert rel.source_name == "auth.ex"
      assert rel.relation == :caused_by
      assert rel.target_kind == :error
      assert_in_delta rel.confidence, 0.5, 0.001
    end

    test "evidence includes tool name" do
      ops = ToolError.extract(error_occurrence("timeout", tool: "Bash", files: ["a.ex"]))
      [rel] = for {:upsert_relationship, attrs} <- ops, do: attrs

      assert rel.evidence =~ "Bash"
    end

    test "no files produces error node only" do
      ops = ToolError.extract(error_occurrence("timeout"))
      assert length(ops) == 1
      assert [{:upsert_node, %{kind: :error}}] = ops
    end
  end
end
