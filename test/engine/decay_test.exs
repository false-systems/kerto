defmodule Kerto.Engine.DecayTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.{Decay, Store}
  alias Kerto.Ingestion.{Occurrence, Source}

  defp make_occurrence(ulid) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new("ci.run.failed", %{files: ["auth.go"], task: "test"}, source)
  end

  setup do
    store = start_supervised!({Store, name: :decay_test_store})

    # Use a very short interval so we can test the timer fires
    decay =
      start_supervised!(
        {Decay, store: :decay_test_store, interval_ms: 50, factor: 0.5, name: :test_decay}
      )

    %{store: store, decay: decay}
  end

  describe "manual tick" do
    test "decay reduces relevance when triggered", %{store: store, decay: decay} do
      Store.ingest(store, make_occurrence("01JABC"))
      {:ok, before} = Store.get_node(store, :file, "auth.go")

      Decay.tick(decay)

      {:ok, after_decay} = Store.get_node(store, :file, "auth.go")
      assert after_decay.relevance < before.relevance
    end
  end

  describe "automatic timer" do
    test "timer fires and applies decay", %{store: store} do
      Store.ingest(store, make_occurrence("01JABC"))
      {:ok, before} = Store.get_node(store, :file, "auth.go")

      # Wait for at least one timer tick (50ms interval)
      Process.sleep(100)

      {:ok, after_decay} = Store.get_node(store, :file, "auth.go")
      assert after_decay.relevance < before.relevance
    end
  end

  describe "status/1" do
    test "returns decay stats", %{decay: decay} do
      status = Decay.status(decay)
      assert is_map(status)
      assert Map.has_key?(status, :ticks)
      assert Map.has_key?(status, :factor)
    end

    test "tick count increments", %{decay: decay} do
      Decay.tick(decay)
      Decay.tick(decay)
      status = Decay.status(decay)
      assert status.ticks >= 2
    end
  end
end
