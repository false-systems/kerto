defmodule Kerto.Graph.NodeKindTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.NodeKind

  describe "valid?/1" do
    test "accepts all defined kinds" do
      for kind <- [:file, :module, :pattern, :decision, :error, :concept] do
        assert NodeKind.valid?(kind), "expected #{kind} to be valid"
      end
    end

    test "rejects unknown atoms" do
      refute NodeKind.valid?(:banana)
    end

    test "rejects non-atoms" do
      refute NodeKind.valid?("file")
    end
  end

  describe "all/0" do
    test "returns all six kinds" do
      assert length(NodeKind.all()) == 6
    end

    test "returns atoms" do
      assert Enum.all?(NodeKind.all(), &is_atom/1)
    end
  end
end
