defmodule Kerto.Interface.Command.UnpinTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.{Pin, Unpin}
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_unpin_engine

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

  describe "unpin node" do
    test "unpins a pinned node" do
      Pin.execute(@engine, %{node: "auth.go", kind: :file})
      resp = Unpin.execute(@engine, %{node: "auth.go", kind: :file})
      assert resp.ok

      {:ok, node} = Kerto.Engine.get_node(@engine, :file, "auth.go")
      assert node.pinned == false
    end

    test "returns error for missing node" do
      resp = Unpin.execute(@engine, %{node: "nope.go", kind: :file})
      refute resp.ok
      assert resp.error =~ "not found"
    end
  end

  describe "unpin relationship" do
    test "unpins a pinned relationship" do
      Pin.execute(@engine, %{
        source: "auth.go",
        relation: :breaks,
        target: "test",
        source_kind: :file,
        target_kind: :module
      })

      resp =
        Unpin.execute(@engine, %{
          source: "auth.go",
          relation: :breaks,
          target: "test",
          source_kind: :file,
          target_kind: :module
        })

      assert resp.ok
    end
  end

  describe "missing args" do
    test "returns error when no args given" do
      resp = Unpin.execute(@engine, %{})
      refute resp.ok
    end
  end
end
