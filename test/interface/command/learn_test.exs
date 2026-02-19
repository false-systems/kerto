defmodule Kerto.Interface.Command.LearnTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Learn

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_learn_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_learn_engine}
  end

  test "creates a learning with subject and target", %{engine: engine} do
    args = %{
      evidence: "auth.go OOM caused by unbounded cache",
      subject: "auth.go",
      subject_kind: :file,
      relation: :caused_by,
      target: "unbounded cache",
      target_kind: :concept
    }

    resp = Learn.execute(engine, args)
    assert resp.ok

    assert {:ok, node} = Kerto.Engine.get_node(engine, :file, "auth.go")
    assert node.name == "auth.go"
    assert {:ok, _} = Kerto.Engine.get_node(engine, :concept, "unbounded cache")
  end

  test "creates a learning with subject only (no target)", %{engine: engine} do
    args = %{
      evidence: "parser has quadratic complexity",
      subject: "parser.go",
      subject_kind: :file
    }

    resp = Learn.execute(engine, args)
    assert resp.ok
    assert {:ok, _} = Kerto.Engine.get_node(engine, :file, "parser.go")
  end

  test "defaults subject_kind to :file", %{engine: engine} do
    args = %{evidence: "test learning", subject: "handler.go"}
    resp = Learn.execute(engine, args)
    assert resp.ok
    assert {:ok, node} = Kerto.Engine.get_node(engine, :file, "handler.go")
    assert node.kind == :file
  end

  test "returns error when subject is missing", %{engine: engine} do
    resp = Learn.execute(engine, %{evidence: "something"})
    refute resp.ok
    assert resp.error =~ "subject"
  end

  test "returns error when evidence is missing", %{engine: engine} do
    resp = Learn.execute(engine, %{subject: "auth.go"})
    refute resp.ok
    assert resp.error =~ "evidence"
  end
end
