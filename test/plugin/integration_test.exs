defmodule Kerto.Plugin.IntegrationTest do
  @moduledoc """
  Integration test: plugin → occurrence → extraction → graph.
  """
  use ExUnit.Case, async: false

  alias Kerto.Engine.PluginRunner
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_plugin_integration_engine

  defmodule MultiOccurrencePlugin do
    @behaviour Kerto.Plugin

    @impl true
    def agent_name, do: "multi"

    @impl true
    def scan(_last_sync) do
      source = Source.new("test-plugin", "multi", "01JMULTI")

      [
        Occurrence.new("agent.file_read", %{file: "integration.ex"}, source),
        Occurrence.new(
          "agent.approach_abandoned",
          %{
            subject: "integration.ex",
            approach: "brute force",
            reason: "too slow"
          },
          source
        )
      ]
    end
  end

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    :ok
  end

  test "plugin occurrences flow through extraction into graph" do
    runner =
      start_supervised!(
        {PluginRunner,
         name: :test_pi_full,
         engine: @engine,
         plugins: [MultiOccurrencePlugin],
         interval_ms: :infinity}
      )

    PluginRunner.scan_now(runner)

    # File read should create a file node
    {:ok, file_node} = Kerto.Engine.get_node(@engine, :file, "integration.ex")
    assert file_node.name == "integration.ex"

    # Approach abandoned should create a pattern node
    {:ok, pattern_node} = Kerto.Engine.get_node(@engine, :pattern, "brute force")
    assert pattern_node.name == "brute force"

    # Should have relationships
    graph = Kerto.Engine.get_graph(@engine)
    rels = Kerto.Graph.Graph.list_relationships(graph, relation: :tried_failed)
    assert length(rels) == 1
    assert hd(rels).evidence == ["too slow"]
  end
end
