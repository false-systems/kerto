defmodule Kerto.Engine.Config do
  @moduledoc """
  Runtime configuration with sensible defaults.

  Pure module — no GenServer. Config is read at startup and passed
  to processes that need it. If config changes, restart the process.
  """

  @defaults %{
    ewma_alpha: 0.3,
    decay_factor: 0.95,
    decay_interval_ms: :timer.hours(6),
    death_threshold_edge: 0.05,
    death_threshold_node: 0.01,
    max_occurrences: 1024,
    snapshot_interval_ms: :timer.minutes(30)
  }

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec get(atom()) :: term()
  def get(key) when is_atom(key) do
    Map.get(@defaults, key)
  end

  @spec get(atom(), term()) :: term()
  def get(key, fallback) when is_atom(key) do
    Map.get(@defaults, key, fallback)
  end
end
