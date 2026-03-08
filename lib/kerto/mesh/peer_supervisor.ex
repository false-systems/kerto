defmodule Kerto.Mesh.PeerSupervisor do
  @moduledoc """
  DynamicSupervisor managing Peer GenServers per connected peer.

  Starts/stops Peer processes as peers are discovered or disconnected.
  Handles duplicate start attempts gracefully.
  """

  use DynamicSupervisor

  alias Kerto.Mesh.Peer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_peer(GenServer.server(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_peer(supervisor \\ __MODULE__, peer_opts) do
    child_spec = {Peer, peer_opts}

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @spec stop_peer(GenServer.server(), GenServer.server()) :: :ok | {:error, :not_found}
  def stop_peer(supervisor \\ __MODULE__, peer_name) do
    case GenServer.whereis(peer_name) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(supervisor, pid)
    end
  end

  @spec connected_peers(GenServer.server()) :: [pid()]
  def connected_peers(supervisor \\ __MODULE__) do
    supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
