defmodule Kerto.Ingestion.SourceTest do
  use ExUnit.Case, async: true

  alias Kerto.Ingestion.Source

  describe "new/3" do
    test "creates source with required fields" do
      source = Source.new("github-actions", "ci-bot", "01JABC")
      assert source.system == "github-actions"
      assert source.agent == "ci-bot"
      assert source.ulid == "01JABC"
    end

    test "enforces binary arguments" do
      assert_raise FunctionClauseError, fn ->
        Source.new(:github, "ci-bot", "01JABC")
      end
    end

    test "preserves exact values" do
      source = Source.new("gitlab", "deploy-agent", "01JXYZ")
      assert source.system == "gitlab"
      assert source.agent == "deploy-agent"
      assert source.ulid == "01JXYZ"
    end
  end

  describe "struct" do
    test "enforces all keys" do
      assert_raise ArgumentError, fn ->
        struct!(Source, system: "x", agent: "y")
      end
    end

    test "is a proper struct" do
      source = Source.new("system", "agent", "01JABC")
      assert %Source{} = source
    end
  end
end
