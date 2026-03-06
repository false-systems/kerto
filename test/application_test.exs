defmodule Kerto.ApplicationTest do
  use ExUnit.Case, async: false

  test "starts the application with engine running" do
    # Application may already be started by mix test, or we start it here
    case Application.ensure_all_started(:kerto) do
      {:ok, _} -> :ok
      {:error, {:already_started, :kerto}} -> :ok
    end

    # The engine should be registered as :kerto_engine
    assert Process.whereis(:kerto_engine) != nil
  end

  test "engine is functional after application start" do
    case Application.ensure_all_started(:kerto) do
      {:ok, _} -> :ok
      {:error, {:already_started, :kerto}} -> :ok
    end

    status = Kerto.Engine.status(:kerto_engine)
    assert is_map(status)
    assert Map.has_key?(status, :nodes)
  end

  describe "load_plugins/1" do
    @tag :tmp_dir
    test "returns plugin list from valid plugins.exs", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), "[Kerto.Plugin.Claude]")

      assert Kerto.Application.load_plugins(dir) == [Kerto.Plugin.Claude]
    end

    @tag :tmp_dir
    test "returns empty list when plugins.exs is missing", %{tmp_dir: dir} do
      assert Kerto.Application.load_plugins(dir) == []
    end

    @tag :tmp_dir
    test "returns empty list when plugins.exs has invalid Elixir", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), "not valid elixir !!!")

      assert Kerto.Application.load_plugins(dir) == []
    end

    @tag :tmp_dir
    test "returns empty list when plugins.exs returns non-list", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), ":not_a_list")

      assert Kerto.Application.load_plugins(dir) == []
    end

    @tag :tmp_dir
    test "returns empty list when plugins.exs contains non-atom entry", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), ~s(["not_a_module"]))

      assert Kerto.Application.load_plugins(dir) == []
    end

    @tag :tmp_dir
    test "handles multiple plugins", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), "[Kerto.Plugin.Claude, Kerto.Plugin.Logs]")

      assert Kerto.Application.load_plugins(dir) == [Kerto.Plugin.Claude, Kerto.Plugin.Logs]
    end

    @tag :tmp_dir
    test "handles empty list", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "plugins.exs"), "[]")

      assert Kerto.Application.load_plugins(dir) == []
    end
  end
end
