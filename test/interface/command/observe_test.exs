defmodule Kerto.Interface.Command.ObserveTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Observe

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_observe_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_observe_engine}
  end

  test "creates concept node from summary", %{engine: engine} do
    args = %{summary: "Fixed OOM in auth module"}
    resp = Observe.execute(engine, args)
    assert resp.ok

    assert {:ok, node} = Kerto.Engine.get_node(engine, :concept, "fixed-oom-in-auth-module")
    assert node.kind == :concept
  end

  test "creates file nodes for each file", %{engine: engine} do
    args = %{summary: "Refactored caching", files: ["auth.go", "cache.go"]}
    resp = Observe.execute(engine, args)
    assert resp.ok

    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "auth.go")
    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "cache.go")
  end

  test "returns error when summary is missing", %{engine: engine} do
    resp = Observe.execute(engine, %{})
    refute resp.ok
    assert resp.error =~ "summary"
  end

  test "works with empty files list", %{engine: engine} do
    args = %{summary: "Explored the codebase", files: []}
    resp = Observe.execute(engine, args)
    assert resp.ok
  end

  test "works without files key", %{engine: engine} do
    args = %{summary: "Quick session"}
    resp = Observe.execute(engine, args)
    assert resp.ok
  end
end
