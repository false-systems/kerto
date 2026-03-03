defmodule Kerto.Mesh.Peer do
  @moduledoc """
  Level 3: Per-peer sync state machine GenServer.

  Drives the sync protocol defined in ADR-007, consuming pure `Sync.*`
  functions to exchange occurrences between BEAM nodes.

  State machine: Idle → Handshake → Replaying → Live

  Uses `peer_ref` for message delivery — a pid in tests, a
  `{module, node_atom}` tuple in production. This keeps the GenServer
  testable without real BEAM distribution.
  """

  use GenServer

  alias Kerto.Engine
  alias Kerto.Mesh.Sync

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec connect(GenServer.server()) :: :ok | {:error, :not_idle}
  def connect(server), do: GenServer.call(server, :connect)

  @spec status(GenServer.server()) :: %{peer: String.t(), status: atom()}
  def status(server), do: GenServer.call(server, :status)

  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(server), do: GenServer.call(server, :disconnect)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    peer_node = Keyword.fetch!(opts, :peer_node)
    engine = Keyword.fetch!(opts, :engine)
    peer_ref = Keyword.fetch!(opts, :peer_ref)
    my_node = Keyword.get(opts, :my_node, to_string(Node.self()))
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, 100)

    state = %{
      peer_node: peer_node,
      my_node: my_node,
      engine: engine,
      status: :idle,
      sync_points: %{},
      poll_interval_ms: poll_interval_ms,
      peer_live: false,
      we_sent_live: false,
      peer_ref: peer_ref
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{status: :idle} = state) do
    sp = Sync.get_sync_point(state.sync_points, state.peer_node)
    msg = Sync.hello(sp, state.my_node)
    send_to_peer(state.peer_ref, msg)
    {:reply, :ok, %{state | status: :handshake}}
  end

  def handle_call(:connect, _from, state) do
    {:reply, {:error, :not_idle}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{peer: state.peer_node, status: state.status}, state}
  end

  def handle_call(:disconnect, _from, state) do
    {:reply, :ok, %{state | status: :idle, peer_live: false, we_sent_live: false}}
  end

  @impl true
  def handle_info({:sync_hello, peer_sp, peer_name}, state) do
    handle_sync_hello(peer_sp, peer_name, state)
  end

  def handle_info({:sync_occurrence, occ}, state) do
    if Sync.should_sync?(occ) do
      Engine.ingest(state.engine, occ)
      ulid = occ.source.ulid
      sync_points = Sync.update_sync_point(state.sync_points, state.peer_node, ulid)
      {:noreply, %{state | sync_points: sync_points}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:sync_live, %{status: :live} = state) do
    {:noreply, state}
  end

  def handle_info(:sync_live, %{we_sent_live: true} = state) do
    schedule_poll(state.poll_interval_ms)
    {:noreply, %{state | status: :live, peer_live: true}}
  end

  def handle_info(:sync_live, state) do
    {:noreply, %{state | peer_live: true}}
  end

  def handle_info(:poll, %{status: :live} = state) do
    sp = Sync.get_sync_point(state.sync_points, state.my_node)
    occs = Engine.occurrences_since(state.engine, sp)
    syncable = Sync.filter_syncable(occs)

    Enum.each(syncable, fn occ ->
      send_to_peer(state.peer_ref, {:sync_occurrence, occ})
    end)

    new_sp = advance_sync_point(sp, occs)
    sync_points = maybe_update_sync_point(state.sync_points, state.my_node, new_sp)

    schedule_poll(state.poll_interval_ms)
    {:noreply, %{state | sync_points: sync_points}}
  end

  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({:nodedown, node}, state) when is_atom(node) do
    if Atom.to_string(node) == state.peer_node do
      {:noreply, %{state | status: :idle, peer_live: false, we_sent_live: false}}
    else
      {:noreply, state}
    end
  end

  # --- Private ---

  defp handle_sync_hello(peer_sp, _peer_name, %{status: :idle} = state) do
    # Remote-initiated: respond with our hello + replay
    sp = Sync.get_sync_point(state.sync_points, state.peer_node)
    msg = Sync.hello(sp, state.my_node)
    send_to_peer(state.peer_ref, msg)

    state = replay_occurrences(state, peer_sp)
    send_to_peer(state.peer_ref, Sync.live())
    {:noreply, finish_replay(state)}
  end

  defp handle_sync_hello(peer_sp, _peer_name, %{status: :handshake} = state) do
    state = replay_occurrences(state, peer_sp)
    send_to_peer(state.peer_ref, Sync.live())
    {:noreply, finish_replay(state)}
  end

  defp handle_sync_hello(_peer_sp, _peer_name, state) do
    {:noreply, state}
  end

  defp replay_occurrences(state, peer_sp) do
    occs = Engine.occurrences_since(state.engine, peer_sp)
    syncable = Sync.filter_syncable(occs)

    Enum.each(syncable, fn occ ->
      send_to_peer(state.peer_ref, {:sync_occurrence, occ})
    end)

    # Advance our sync point past what we just sent
    new_sp = advance_sync_point(nil, occs)
    sync_points = maybe_update_sync_point(state.sync_points, state.my_node, new_sp)
    %{state | sync_points: sync_points}
  end

  defp finish_replay(%{peer_live: true} = state) do
    schedule_poll(state.poll_interval_ms)
    %{state | status: :live, we_sent_live: true}
  end

  defp finish_replay(state) do
    %{state | status: :replaying, we_sent_live: true}
  end

  defp advance_sync_point(current_sp, []), do: current_sp

  defp advance_sync_point(_current_sp, occs) do
    occs |> List.last() |> Map.get(:source) |> Map.get(:ulid)
  end

  defp maybe_update_sync_point(points, _node, nil), do: points

  defp maybe_update_sync_point(points, node, sp) do
    Sync.update_sync_point(points, node, sp)
  end

  defp send_to_peer(pid, msg) when is_pid(pid), do: send(pid, msg)

  defp send_to_peer({mod, node}, msg) do
    send({mod, node}, msg)
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
