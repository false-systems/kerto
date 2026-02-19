defmodule Kerto.Interface.DispatcherTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Dispatcher

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_dispatch_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_dispatch_engine}
  end

  test "dispatches status command", %{engine: engine} do
    resp = Dispatcher.dispatch("status", engine, %{})
    assert resp.ok
    assert Map.has_key?(resp.data, :nodes)
  end

  test "dispatches context command", %{engine: engine} do
    resp = Dispatcher.dispatch("context", engine, %{name: "nope.go"})
    refute resp.ok
  end

  test "returns error for unknown command", %{engine: engine} do
    resp = Dispatcher.dispatch("explode", engine, %{})
    refute resp.ok
    assert resp.error =~ "unknown command"
  end

  test "all registered commands are dispatchable", %{engine: engine} do
    commands = Dispatcher.commands()
    assert "status" in commands
    assert "context" in commands
    assert "learn" in commands
    assert "decide" in commands
    assert "ingest" in commands
    assert "graph" in commands
    assert "decay" in commands
    assert "weaken" in commands
    assert "delete" in commands
  end
end
