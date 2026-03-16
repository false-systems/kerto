defmodule Kerto.Engine.PluginRunner do
  @moduledoc """
  Periodic plugin scanner. Calls each registered plugin's scan/1
  and ingests returned occurrences into the engine.

  Tracks a ULID sync point per plugin so each scan only processes
  new data since the last run.
  """

  use GenServer

  require Logger

  alias Kerto.Graph.ULID

  @default_interval_ms :timer.minutes(5)

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec scan_now(GenServer.server()) :: :ok
  def scan_now(server \\ __MODULE__) do
    GenServer.call(server, :scan_now)
  end

  @spec last_syncs(GenServer.server()) :: map()
  def last_syncs(server \\ __MODULE__) do
    GenServer.call(server, :last_syncs)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    engine = Keyword.fetch!(opts, :engine)
    plugins = Keyword.get(opts, :plugins, [])

    if interval != :infinity, do: schedule_tick(interval)

    {:ok, %{interval: interval, engine: engine, plugins: plugins, last_syncs: %{}}}
  end

  @impl true
  def handle_call(:scan_now, _from, state) do
    state = run_all_plugins(state)
    {:reply, :ok, state}
  end

  def handle_call(:last_syncs, _from, state) do
    {:reply, state.last_syncs, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = run_all_plugins(state)
    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp run_all_plugins(state) do
    Enum.reduce(state.plugins, state, fn plugin, acc ->
      run_plugin(acc, plugin)
    end)
  end

  defp run_plugin(state, plugin) do
    last_sync = Map.get(state.last_syncs, plugin)
    sync_point = ULID.generate()

    occurrences =
      try do
        plugin.scan(last_sync)
      rescue
        e ->
          Logger.error("Plugin #{plugin.agent_name()} scan failed: #{Exception.message(e)}")
          []
      end

    Enum.each(occurrences, fn occ ->
      Kerto.Engine.ingest(state.engine, occ)
    end)

    %{state | last_syncs: Map.put(state.last_syncs, plugin, sync_point)}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
