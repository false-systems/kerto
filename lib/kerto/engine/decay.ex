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

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    factor = Keyword.get(opts, :factor, @default_factor)
    store = Keyword.get(opts, :store, Store)

    schedule_tick(interval)

    {:ok, %{interval: interval, factor: factor, store: store}}
  end

  @impl true
  def handle_info(:tick, state) do
    Store.decay(state.store, state.factor)
    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
