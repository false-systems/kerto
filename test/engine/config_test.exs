defmodule Kerto.Engine.ConfigTest do
  use ExUnit.Case, async: true

  alias Kerto.Engine.Config

  describe "defaults/0" do
    test "returns a map with all required keys" do
      defaults = Config.defaults()
      assert is_map(defaults)
      assert Map.has_key?(defaults, :ewma_alpha)
      assert Map.has_key?(defaults, :decay_factor)
      assert Map.has_key?(defaults, :decay_interval_ms)
      assert Map.has_key?(defaults, :max_occurrences)
    end

    test "ewma_alpha is 0.3" do
      assert Config.defaults().ewma_alpha == 0.3
    end

    test "decay_factor is 0.95" do
      assert Config.defaults().decay_factor == 0.95
    end

    test "max_occurrences is 1024" do
      assert Config.defaults().max_occurrences == 1024
    end
  end

  describe "get/1" do
    test "returns default value for known key" do
      assert Config.get(:ewma_alpha) == 0.3
      assert Config.get(:decay_factor) == 0.95
    end

    test "returns nil for unknown key" do
      assert Config.get(:nonexistent) == nil
    end
  end

  describe "get/2 with fallback" do
    test "returns default when key exists" do
      assert Config.get(:ewma_alpha, 0.5) == 0.3
    end

    test "returns fallback for unknown key" do
      assert Config.get(:nonexistent, 42) == 42
    end
  end
end
