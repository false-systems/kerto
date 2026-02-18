defmodule Kerto.Engine.Decay do
  @moduledoc """
  Periodic decay timer. Calls Store.decay/2 on each tick.

  Thin process — knows nothing about graphs or EWMA. Just a timer
  that triggers decay at the configured interval.
  """

  use GenServer

  alias Kerto.Engine.Store

  @default_interval_ms :timer.hours(6)
  @default_factor 0.95

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec tick(GenServer.server()) :: :ok
  def tick(server \\ __MODULE__) do
    GenServer.call(server, :tick)
  end

  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    factor = Keyword.get(opts, :factor, @default_factor)
    store = Keyword.get(opts, :store, Store)

    schedule_tick(interval)

    {:ok, %{interval: interval, factor: factor, store: store, ticks: 0}}
  end

  @impl true
  def handle_call(:tick, _from, state) do
    Store.decay(state.store, state.factor)
    {:reply, :ok, %{state | ticks: state.ticks + 1}}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{ticks: state.ticks, factor: state.factor, interval_ms: state.interval}, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Store.decay(state.store, state.factor)
    schedule_tick(state.interval)
    {:noreply, %{state | ticks: state.ticks + 1}}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
