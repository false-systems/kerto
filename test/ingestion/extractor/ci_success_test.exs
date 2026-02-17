defmodule Kerto.Ingestion.Extractor.CiSuccessTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.{Extractor.CiSuccess, Occurrence, Source}

  @source Source.new("github-actions", "ci-bot", "01JABC")

  defp success_occurrence(data) do
    Occurrence.new("ci.run.passed", data, @source)
  end

  describe "extract/1" do
    test "creates weak file node observations" do
      occ = success_occurrence(%{files: ["auth.go", "handler.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      file_nodes = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs

      assert length(file_nodes) == 2
      assert Enum.all?(file_nodes, &(&1.confidence == 0.1))
    end

    test "creates weaken_relationship ops for each file" do
      occ = success_occurrence(%{files: ["auth.go", "handler.go"], task: "test"})
      ops = CiSuccess.extract(occ)

      weakens = for {:weaken_relationship, attrs} <- ops, do: attrs
      assert length(weakens) == 2
    end

    test "weaken ops target :breaks relationship" do
      occ = success_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      [weaken] = for {:weaken_relationship, attrs} <- ops, do: attrs

      assert weaken.relation == :breaks
      assert weaken.source_name == "auth.go"
      assert weaken.target_name == "test"
    end

    test "weaken factor is 0.5" do
      occ = success_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      [weaken] = for {:weaken_relationship, attrs} <- ops, do: attrs

      assert_in_delta weaken.factor, 0.5, 0.001
    end

    test "empty files returns empty ops" do
      occ = success_occurrence(%{files: [], task: "test"})
      ops = CiSuccess.extract(occ)
      assert ops == []
    end

    test "file node kind is :file" do
      occ = success_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      file_nodes = for {:upsert_node, %{kind: :file} = attrs} <- ops, do: attrs
      assert length(file_nodes) == 1
      assert hd(file_nodes).kind == :file
    end

    test "weaken op source and target kinds are correct" do
      occ = success_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      [weaken] = for {:weaken_relationship, attrs} <- ops, do: attrs

      assert weaken.source_kind == :file
      assert weaken.target_kind == :module
    end

    test "creates task module node" do
      occ = success_occurrence(%{files: ["auth.go"], task: "test"})
      ops = CiSuccess.extract(occ)
      module_nodes = for {:upsert_node, %{kind: :module} = attrs} <- ops, do: attrs

      assert length(module_nodes) == 1
      assert hd(module_nodes).name == "test"
    end
  end
end
