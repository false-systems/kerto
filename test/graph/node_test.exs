defmodule Kerto.Graph.NodeTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.Node
  alias Kerto.Graph.Identity

  @file_id Identity.compute_id(:file, "auth.go")

  describe "new/3" do
    test "creates a node with computed id" do
      node = Node.new(:file, "auth.go", "01JABC")
      assert node.id == @file_id
      assert node.name == "auth.go"
      assert node.kind == :file
    end

    test "sets initial relevance to 0.5" do
      node = Node.new(:file, "auth.go", "01JABC")
      assert node.relevance == 0.5
    end

    test "sets observations to 1" do
      node = Node.new(:file, "auth.go", "01JABC")
      assert node.observations == 1
    end

    test "sets first_seen and last_seen to the given ULID" do
      node = Node.new(:file, "auth.go", "01JABC")
      assert node.first_seen == "01JABC"
      assert node.last_seen == "01JABC"
    end

    test "canonicalizes file paths" do
      node = Node.new(:file, "./src/../src/auth.go", "01JABC")
      assert node.name == "src/auth.go"
      assert node.id == Identity.compute_id(:file, "src/auth.go")
    end

    test "summary is nil initially" do
      node = Node.new(:file, "auth.go", "01JABC")
      assert node.summary == nil
    end

    test "rejects invalid kind" do
      assert_raise MatchError, fn ->
        Node.new(:banana, "auth.go", "01JABC")
      end
    end
  end

  describe "observe/3" do
    test "reinforces relevance via EWMA" do
      node = Node.new(:file, "auth.go", "01JABC")
      observed = Node.observe(node, 1.0, "01JDEF")

      # EWMA: 0.3 * 1.0 + 0.7 * 0.5 = 0.65
      assert_in_delta observed.relevance, 0.65, 0.001
    end

    test "increments observation count" do
      node = Node.new(:file, "auth.go", "01JABC")
      observed = Node.observe(node, 1.0, "01JDEF")
      assert observed.observations == 2
    end

    test "updates last_seen" do
      node = Node.new(:file, "auth.go", "01JABC")
      observed = Node.observe(node, 1.0, "01JDEF")
      assert observed.last_seen == "01JDEF"
      assert observed.first_seen == "01JABC"
    end

    test "does not change id, name, or kind" do
      node = Node.new(:file, "auth.go", "01JABC")
      observed = Node.observe(node, 1.0, "01JDEF")
      assert observed.id == node.id
      assert observed.name == node.name
      assert observed.kind == node.kind
    end
  end

  describe "decay/2" do
    test "reduces relevance by factor" do
      node = Node.new(:file, "auth.go", "01JABC")
      decayed = Node.decay(node, 0.95)
      assert_in_delta decayed.relevance, 0.475, 0.001
    end

    test "uses default factor" do
      node = Node.new(:file, "auth.go", "01JABC")
      decayed = Node.decay(node)
      assert_in_delta decayed.relevance, 0.475, 0.001
    end
  end

  describe "dead?/1" do
    test "node at 0.5 relevance is not dead" do
      node = Node.new(:file, "auth.go", "01JABC")
      refute Node.dead?(node)
    end

    test "node below 0.01 is dead" do
      node = Node.new(:file, "auth.go", "01JABC")
      # Decay many times to get below 0.01
      dying = Enum.reduce(1..100, node, fn _, n -> Node.decay(n, 0.9) end)
      assert Node.dead?(dying)
    end
  end
end
