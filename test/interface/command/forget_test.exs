defmodule Kerto.Interface.Command.ForgetTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Forget
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_forget_engine

  setup do
    start_supervised!({Kerto.Engine, name: @engine, decay_interval_ms: :timer.hours(1)})

    occ =
      Occurrence.new(
        "ci.run.failed",
        %{files: ["auth.go"], task: "test"},
        Source.new("sykli", "ci", "01JABC")
      )

    Kerto.Engine.ingest(@engine, occ)
    :ok
  end

  describe "forget node" do
    test "forgets an existing node" do
      resp = Forget.execute(@engine, %{node: "auth.go", kind: :file})
      assert resp.ok
      assert :error = Kerto.Engine.get_node(@engine, :file, "auth.go")
    end

    test "returns error for missing node" do
      resp = Forget.execute(@engine, %{node: "nope.go", kind: :file})
      refute resp.ok
      assert resp.error =~ "not found"
    end

    test "defaults kind to :file" do
      resp = Forget.execute(@engine, %{node: "auth.go"})
      assert resp.ok
    end
  end

  describe "forget relationship" do
    test "forgets an existing relationship" do
      resp =
        Forget.execute(@engine, %{
          source: "auth.go",
          relation: :breaks,
          target: "test",
          source_kind: :file,
          target_kind: :module
        })

      assert resp.ok
    end

    test "returns error for missing relationship" do
      resp =
        Forget.execute(@engine, %{
          source: "nope.go",
          relation: :breaks,
          target: "other",
          source_kind: :file,
          target_kind: :file
        })

      refute resp.ok
    end
  end

  describe "missing args" do
    test "returns error when no args given" do
      resp = Forget.execute(@engine, %{})
      refute resp.ok
      assert resp.error =~ "specify"
    end
  end
end
