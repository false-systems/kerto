defmodule Kerto.Interface.Command.PinTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Pin
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_pin_engine

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

  describe "pin node" do
    test "pins an existing node" do
      resp = Pin.execute(@engine, %{node: "auth.go", kind: :file})
      assert resp.ok

      {:ok, node} = Kerto.Engine.get_node(@engine, :file, "auth.go")
      assert node.pinned == true
    end

    test "returns error for missing node" do
      resp = Pin.execute(@engine, %{node: "nope.go", kind: :file})
      refute resp.ok
      assert resp.error =~ "not found"
    end
  end

  describe "pin relationship" do
    test "pins an existing relationship" do
      resp =
        Pin.execute(@engine, %{
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
        Pin.execute(@engine, %{
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
      resp = Pin.execute(@engine, %{})
      refute resp.ok
      assert resp.error =~ "specify"
    end
  end
end
