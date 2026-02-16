defmodule Kerto.Graph.RelationshipTest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.{Relationship, Identity}

  @source_id Identity.compute_id(:file, "auth.go")
  @target_id Identity.compute_id(:file, "login_test.go")

  describe "new/5" do
    test "creates a relationship with composite identity" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      assert rel.source == @source_id
      assert rel.target == @target_id
      assert rel.relation == :breaks
    end

    test "sets initial weight to 0.5" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      assert rel.weight == 0.5
    end

    test "sets observations to 1" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      assert rel.observations == 1
    end

    test "sets first_seen and last_seen" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      assert rel.first_seen == "01JABC"
      assert rel.last_seen == "01JABC"
    end

    test "initializes with evidence text" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC", "CI failure linked these")
      assert rel.evidence == ["CI failure linked these"]
    end

    test "empty evidence when no text given" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      assert rel.evidence == []
    end

    test "rejects invalid relation type" do
      assert_raise MatchError, fn ->
        Relationship.new(@source_id, :banana, @target_id, "01JABC")
      end
    end
  end

  describe "reinforce/4" do
    test "updates weight via EWMA" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      reinforced = Relationship.reinforce(rel, 1.0, "01JDEF", "new evidence")

      # EWMA: 0.3 * 1.0 + 0.7 * 0.5 = 0.65
      assert_in_delta reinforced.weight, 0.65, 0.001
    end

    test "increments observations" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      reinforced = Relationship.reinforce(rel, 1.0, "01JDEF", "new evidence")
      assert reinforced.observations == 2
    end

    test "appends evidence" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC", "first")
      reinforced = Relationship.reinforce(rel, 1.0, "01JDEF", "second")
      assert reinforced.evidence == ["first", "second"]
    end

    test "updates last_seen" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      reinforced = Relationship.reinforce(rel, 1.0, "01JDEF", "evidence")
      assert reinforced.last_seen == "01JDEF"
      assert reinforced.first_seen == "01JABC"
    end

    test "does not change source, target, or relation" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      reinforced = Relationship.reinforce(rel, 1.0, "01JDEF", "evidence")
      assert reinforced.source == rel.source
      assert reinforced.target == rel.target
      assert reinforced.relation == rel.relation
    end
  end

  describe "weaken/2" do
    test "reduces weight by factor" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      weakened = Relationship.weaken(rel, 0.5)
      assert_in_delta weakened.weight, 0.25, 0.001
    end
  end

  describe "decay/2" do
    test "reduces weight by decay factor" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      decayed = Relationship.decay(rel, 0.95)
      assert_in_delta decayed.weight, 0.475, 0.001
    end

    test "uses default factor" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      decayed = Relationship.decay(rel)
      assert_in_delta decayed.weight, 0.475, 0.001
    end
  end

  describe "dead?/1" do
    test "relationship at 0.5 is not dead" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      refute Relationship.dead?(rel)
    end

    test "relationship below 0.05 is dead" do
      rel = Relationship.new(@source_id, :breaks, @target_id, "01JABC")
      dying = Enum.reduce(1..60, rel, fn _, r -> Relationship.decay(r, 0.9) end)
      assert Relationship.dead?(dying)
    end
  end
end
