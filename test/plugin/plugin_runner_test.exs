defmodule Kerto.Engine.PluginRunnerTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.PluginRunner
  alias Kerto.Ingestion.{Occurrence, Source}

  @engine :test_plugin_runner_engine

  defmodule FakePlugin do
    @behaviour Kerto.Plugin

    @impl true
    def agent_name, do: "fake"

    @impl true
    def scan(_last_sync) do
      source = Source.new("fake", "test", "01JFAKE")

      [
        Occurrence.new("agent.file_read", %{file: "from_plugin.ex"}, source)
      ]
    end
  end

  defmodule EmptyPlugin do
    @behaviour Kerto.Plugin

    @impl true
    def agent_name, do: "empty"

    @impl true
    def scan(_last_sync), do: []
  end

  defmodule CrashPlugin do
    @behaviour Kerto.Plugin

    @impl true
    def agent_name, do: "crash"

    @impl true
    def scan(_last_sync), do: raise("boom")
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

  describe "scan_now/1" do
    test "ingests occurrences from plugin into engine" do
      runner =
        start_supervised!(
          {PluginRunner,
           name: :test_pr_ingest, engine: @engine, plugins: [FakePlugin], interval_ms: :infinity}
        )

      PluginRunner.scan_now(runner)
      {:ok, node} = Kerto.Engine.get_node(@engine, :file, "from_plugin.ex")
      assert node.name == "from_plugin.ex"
    end

    test "handles empty plugin results" do
      runner =
        start_supervised!(
          {PluginRunner,
           name: :test_pr_empty, engine: @engine, plugins: [EmptyPlugin], interval_ms: :infinity}
        )

      assert :ok = PluginRunner.scan_now(runner)
    end

    test "survives plugin crash" do
      runner =
        start_supervised!(
          {PluginRunner,
           name: :test_pr_crash, engine: @engine, plugins: [CrashPlugin], interval_ms: :infinity}
        )

      assert :ok = PluginRunner.scan_now(runner)
    end

    test "tracks last_sync per plugin" do
      runner =
        start_supervised!(
          {PluginRunner,
           name: :test_pr_sync,
           engine: @engine,
           plugins: [FakePlugin, EmptyPlugin],
           interval_ms: :infinity}
        )

      PluginRunner.scan_now(runner)
      syncs = PluginRunner.last_syncs(runner)
      assert Map.has_key?(syncs, FakePlugin)
      assert Map.has_key?(syncs, EmptyPlugin)
    end

    test "runs multiple plugins in sequence" do
      runner =
        start_supervised!(
          {PluginRunner,
           name: :test_pr_multi,
           engine: @engine,
           plugins: [FakePlugin, EmptyPlugin],
           interval_ms: :infinity}
        )

      assert :ok = PluginRunner.scan_now(runner)
      {:ok, _node} = Kerto.Engine.get_node(@engine, :file, "from_plugin.ex")
    end
  end
end
