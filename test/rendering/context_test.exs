defmodule Kerto.Rendering.ContextTest do
  use ExUnit.Case, async: true

  alias Kerto.Rendering.Context
  alias Kerto.Graph.{Node, Relationship, Identity}

  @node Node.new(:file, "auth.go", "01JABC")
  @rel Relationship.new(
         Identity.compute_id(:file, "auth.go"),
         :breaks,
         Identity.compute_id(:file, "test.go"),
         "01JABC",
         "CI failure"
       )

  describe "new/3" do
    test "creates context with node, relationships, and lookup" do
      lookup = %{@node.id => @node}
      ctx = Context.new(@node, [@rel], lookup)

      assert ctx.node == @node
      assert ctx.relationships == [@rel]
      assert ctx.node_lookup == lookup
    end

    test "enforces Node struct" do
      assert_raise FunctionClauseError, fn ->
        Context.new(%{id: "x"}, [], %{})
      end
    end

    test "accepts empty relationships" do
      ctx = Context.new(@node, [], %{})
      assert ctx.relationships == []
    end

    test "is a proper struct" do
      ctx = Context.new(@node, [], %{})
      assert %Context{} = ctx
    end
  end
end
