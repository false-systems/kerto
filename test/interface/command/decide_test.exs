defmodule Kerto.Interface.Command.DecideTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Decide

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_decide_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_decide_engine}
  end

  test "records a decision", %{engine: engine} do
    args = %{
      evidence: "stateless requirement, no sessions",
      subject: "auth",
      subject_kind: :module,
      target: "JWT",
      target_kind: :decision
    }

    resp = Decide.execute(engine, args)
    assert resp.ok
    assert {:ok, _} = Kerto.Engine.get_node(engine, :module, "auth")
    assert {:ok, _} = Kerto.Engine.get_node(engine, :decision, "JWT")
  end

  test "returns error when subject is missing", %{engine: engine} do
    resp = Decide.execute(engine, %{evidence: "x", target: "y"})
    refute resp.ok
  end

  test "returns error when target is missing", %{engine: engine} do
    resp = Decide.execute(engine, %{evidence: "x", subject: "y"})
    refute resp.ok
  end

  test "returns error when evidence is missing", %{engine: engine} do
    resp = Decide.execute(engine, %{subject: "x", target: "y"})
    refute resp.ok
  end
end
