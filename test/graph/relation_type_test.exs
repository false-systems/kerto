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
            :often_changes_with,
            :edited_with
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

  describe "inverse_label/1" do
    test "breaks → broken by" do
      assert RelationType.inverse_label(:breaks) == "broken by"
    end

    test "caused_by → causes" do
      assert RelationType.inverse_label(:caused_by) == "causes"
    end

    test "triggers → triggered by" do
      assert RelationType.inverse_label(:triggers) == "triggered by"
    end

    test "depends_on → depended on by" do
      assert RelationType.inverse_label(:depends_on) == "depended on by"
    end

    test "part_of → contains" do
      assert RelationType.inverse_label(:part_of) == "contains"
    end

    test "symmetric types return string of atom" do
      assert RelationType.inverse_label(:often_changes_with) == "often_changes_with"
      assert RelationType.inverse_label(:learned) == "learned"
    end
  end

  describe "all/0" do
    test "returns all eleven types" do
      assert length(RelationType.all()) == 11
    end

    test "returns atoms" do
      assert Enum.all?(RelationType.all(), &is_atom/1)
    end
  end
end
