defmodule Kerto.Graph.EWMATest do
  use ExUnit.Case, async: true

  alias Kerto.Graph.EWMA

  describe "update/2" do
    test "new observation shifts weight toward observation" do
      # α=0.3: new_weight = 0.3 * 1.0 + 0.7 * 0.5 = 0.65
      assert_in_delta EWMA.update(0.5, 1.0), 0.65, 0.001
    end

    test "zero observation pulls weight down" do
      # α=0.3: new_weight = 0.3 * 0.0 + 0.7 * 0.8 = 0.56
      assert_in_delta EWMA.update(0.8, 0.0), 0.56, 0.001
    end

    test "repeated observations converge to observation value" do
      weight = Enum.reduce(1..20, 0.0, fn _, w -> EWMA.update(w, 1.0) end)
      assert_in_delta weight, 1.0, 0.01
    end

    test "same value observation keeps weight stable" do
      assert_in_delta EWMA.update(0.5, 0.5), 0.5, 0.001
    end
  end

  describe "decay/2" do
    test "reduces weight by factor" do
      assert EWMA.decay(1.0, 0.95) == 0.95
    end

    test "10 decay cycles from 1.0" do
      weight = Enum.reduce(1..10, 1.0, fn _, w -> EWMA.decay(w, 0.95) end)
      assert_in_delta weight, 0.5987, 0.001
    end

    test "uses default decay factor" do
      assert EWMA.decay(1.0) == 0.95
    end
  end

  describe "dead?/2" do
    test "below threshold is dead" do
      assert EWMA.dead?(0.04, 0.05) == true
    end

    test "at threshold is not dead" do
      assert EWMA.dead?(0.05, 0.05) == false
    end

    test "above threshold is not dead" do
      assert EWMA.dead?(0.06, 0.05) == false
    end
  end

  describe "clamp/1" do
    test "clamps above 1.0 to 1.0" do
      assert EWMA.clamp(1.5) == 1.0
    end

    test "clamps below 0.0 to 0.0" do
      assert EWMA.clamp(-0.1) == 0.0
    end

    test "passes through values in range" do
      assert EWMA.clamp(0.5) == 0.5
    end
  end
end
