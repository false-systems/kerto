defmodule Kerto.Interface.ParserTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.Parser

  describe "parse/1" do
    test "parses status command" do
      assert {"status", %{}} = Parser.parse(["status"])
    end

    test "parses context with positional name" do
      assert {"context", %{name: "auth.go"}} = Parser.parse(["context", "auth.go"])
    end

    test "parses context with --kind and --depth" do
      {cmd, args} = Parser.parse(["context", "auth", "--kind", "module", "--depth", "3"])
      assert cmd == "context"
      assert args.name == "auth"
      assert args.kind == :module
      assert args.depth == 3
    end

    test "parses learn with evidence and flags" do
      {cmd, args} =
        Parser.parse([
          "learn",
          "auth.go often breaks when cache changes",
          "--subject",
          "auth.go",
          "--target",
          "cache.go",
          "--relation",
          "depends_on"
        ])

      assert cmd == "learn"
      assert args.evidence == "auth.go often breaks when cache changes"
      assert args.subject == "auth.go"
      assert args.target == "cache.go"
      assert args.relation == :depends_on
    end

    test "parses decide with required flags" do
      {cmd, args} =
        Parser.parse([
          "decide",
          "stateless requirement",
          "--subject",
          "auth",
          "--target",
          "JWT"
        ])

      assert cmd == "decide"
      assert args.evidence == "stateless requirement"
      assert args.subject == "auth"
      assert args.target == "JWT"
    end

    test "parses graph with --format" do
      assert {"graph", %{format: :dot}} = Parser.parse(["graph", "--format", "dot"])
    end

    test "parses graph defaults to empty args" do
      assert {"graph", %{}} = Parser.parse(["graph"])
    end

    test "parses decay with --factor" do
      assert {"decay", %{factor: 0.8}} = Parser.parse(["decay", "--factor", "0.8"])
    end

    test "parses weaken with all flags" do
      {cmd, args} =
        Parser.parse([
          "weaken",
          "--source",
          "auth.go",
          "--relation",
          "breaks",
          "--target",
          "login",
          "--source-kind",
          "file",
          "--target-kind",
          "module",
          "--factor",
          "0.3"
        ])

      assert cmd == "weaken"
      assert args.source == "auth.go"
      assert args.relation == :breaks
      assert args.target == "login"
      assert args.source_kind == :file
      assert args.target_kind == :module
      assert args.factor == 0.3
    end

    test "parses delete node" do
      {cmd, args} = Parser.parse(["delete", "--node", "auth.go", "--kind", "file"])
      assert cmd == "delete"
      assert args.node == "auth.go"
      assert args.kind == :file
    end

    test "parses delete relationship" do
      {cmd, args} =
        Parser.parse([
          "delete",
          "--source",
          "auth.go",
          "--relation",
          "breaks",
          "--target",
          "login"
        ])

      assert cmd == "delete"
      assert args.source == "auth.go"
      assert args.relation == :breaks
      assert args.target == "login"
    end

    test "parses ingest with --type" do
      {cmd, args} = Parser.parse(["ingest", "--type", "ci.run.failed"])
      assert cmd == "ingest"
      assert args.type == "ci.run.failed"
    end

    test "parses --json flag for any command" do
      {cmd, args} = Parser.parse(["status", "--json"])
      assert cmd == "status"
      assert args.json == true
    end

    test "returns error for no arguments" do
      assert {:error, "no command given"} = Parser.parse([])
    end

    test "returns unknown command as-is" do
      assert {"explode", %{}} = Parser.parse(["explode"])
    end
  end
end
