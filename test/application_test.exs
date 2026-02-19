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
end
