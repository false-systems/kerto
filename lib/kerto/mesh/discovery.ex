defmodule Kerto.Mesh.Discovery do
  @moduledoc """
  Peer discovery GenServer.

  Currently supports explicit peer lists from `.kerto/peers.conf`.
  mDNS discovery (`_kerto._tcp.local`) is planned for a future release.

  ## peers.conf format

  One peer per line, in the form `name@host`:

      kerto@dev-b.local
      kerto@build-server.internal

  Lines starting with `#` are comments. Blank lines are ignored.
  """

  use GenServer

  require Logger

  alias Kerto.Mesh.{PeerNaming, PeerSupervisor}

  @default_poll_interval_ms :timer.seconds(30)

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec add_peer(GenServer.server(), String.t()) :: :ok
  def add_peer(server \\ __MODULE__, peer_node) do
    GenServer.call(server, {:add_peer, peer_node})
  end

  @spec remove_peer(GenServer.server(), String.t()) :: :ok
  def remove_peer(server \\ __MODULE__, peer_node) do
    GenServer.call(server, {:remove_peer, peer_node})
  end

  @spec known_peers(GenServer.server()) :: [String.t()]
  def known_peers(server \\ __MODULE__) do
    GenServer.call(server, :known_peers)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    engine = Keyword.fetch!(opts, :engine)
    peer_supervisor = Keyword.fetch!(opts, :peer_supervisor)
    peers_conf = Keyword.get(opts, :peers_conf)
    poll_interval = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    explicit_peers =
      if peers_conf do
        load_peers_conf(peers_conf)
      else
        []
      end

    if poll_interval != :infinity, do: schedule_poll(poll_interval)

    {:ok,
     %{
       engine: engine,
       peer_supervisor: peer_supervisor,
       peers: MapSet.new(explicit_peers),
       poll_interval: poll_interval
     }}
  end

  @impl true
  def handle_call({:add_peer, peer_node}, _from, state) do
    state = %{state | peers: MapSet.put(state.peers, peer_node)}
    {:reply, :ok, state}
  end

  def handle_call({:remove_peer, peer_node}, _from, state) do
    state = %{state | peers: MapSet.delete(state.peers, peer_node)}
    # Stop the peer process if running
    case peer_process_name(peer_node) do
      nil -> :ok
      peer_name -> PeerSupervisor.stop_peer(state.peer_supervisor, peer_name)
    end

    {:reply, :ok, state}
  end

  def handle_call(:known_peers, _from, state) do
    {:reply, MapSet.to_list(state.peers), state}
  end

  @impl true
  def handle_info(:poll, state) do
    ensure_peers_connected(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  # --- Private ---

  defp ensure_peers_connected(state) do
    Enum.each(state.peers, fn peer_node ->
      with {:ok, peer_name} <- PeerNaming.process_name(peer_node),
           nil <- GenServer.whereis(peer_name),
           {:ok, peer_ref} <- PeerNaming.peer_ref(peer_node) do
        peer_opts = [
          name: peer_name,
          peer_node: peer_node,
          engine: state.engine,
          peer_ref: peer_ref
        ]

        case PeerSupervisor.start_peer(state.peer_supervisor, peer_opts) do
          {:ok, _pid} ->
            Logger.info("Discovery: started peer process for #{peer_node}")

          {:error, reason} ->
            Logger.error("Discovery: failed to start peer for #{peer_node}: #{inspect(reason)}")
        end
      else
        {:error, :invalid_peer_node} ->
          Logger.warning("Discovery: invalid peer node format: #{peer_node}")

        _pid ->
          :ok
      end
    end)
  end

  defp peer_process_name(peer_node) do
    case PeerNaming.process_name(peer_node) do
      {:ok, name} -> name
      {:error, :invalid_peer_node} -> nil
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp load_peers_conf(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)

      {:error, _} ->
        []
    end
  end
end
