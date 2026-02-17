defmodule Kerto.Mesh.Sync do
  @moduledoc """
  Pure functions for the occurrence sync protocol.

  Handles message construction, occurrence filtering by sync point,
  and sync point management. No side effects — the Peer GenServer
  uses these functions to drive the sync state machine.
  """

  alias Kerto.Ingestion.Occurrence

  @syncable_types ~w(ci.run.failed ci.run.passed vcs.commit context.learning context.decision)

  @spec hello(String.t() | nil, String.t()) :: {:sync_hello, String.t() | nil, String.t()}
  def hello(sync_point, node_name) do
    {:sync_hello, sync_point, node_name}
  end

  @spec live() :: :sync_live
  def live, do: :sync_live

  @spec occurrences_since([Occurrence.t()], String.t() | nil) :: [Occurrence.t()]
  def occurrences_since(occurrences, nil), do: occurrences

  def occurrences_since(occurrences, sync_point) when is_binary(sync_point) do
    Enum.filter(occurrences, fn occ -> occ.source.ulid > sync_point end)
  end

  @spec should_sync?(Occurrence.t()) :: boolean()
  def should_sync?(%Occurrence{type: type}), do: type in @syncable_types

  @spec filter_syncable([Occurrence.t()]) :: [Occurrence.t()]
  def filter_syncable(occurrences) do
    Enum.filter(occurrences, &should_sync?/1)
  end

  @spec update_sync_point(%{String.t() => String.t()}, String.t(), String.t()) :: %{
          String.t() => String.t()
        }
  def update_sync_point(points, peer, ulid)
      when is_map(points) and is_binary(peer) and is_binary(ulid) do
    Map.put(points, peer, ulid)
  end

  @spec get_sync_point(%{String.t() => String.t()}, String.t()) :: String.t() | nil
  def get_sync_point(points, peer) when is_map(points) and is_binary(peer) do
    Map.get(points, peer)
  end
end
