defmodule Kerto.Graph.RelationTypeTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.RelationType

  describe "valid?/1" do
    test "accepts all defined types" do
      for type <- [
            :breaks,
            :caused_by,
            :triggers,
            :depends_on,
            :part_of,
            :learned,
            :decided,
            :tried_failed,
            :often_changes_with
          ] do
        assert RelationType.valid?(type), "expected #{type} to be valid"
      end
    end

    test "rejects unknown atoms" do
      refute RelationType.valid?(:banana)
    end

    test "rejects non-atoms" do
      refute RelationType.valid?("breaks")
    end
  end

  describe "all/0" do
    test "returns all nine types" do
      assert length(RelationType.all()) == 9
    end

    test "returns atoms" do
      assert Enum.all?(RelationType.all(), &is_atom/1)
    end
  end
end
