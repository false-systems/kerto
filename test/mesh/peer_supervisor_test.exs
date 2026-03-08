defmodule Kerto.Mesh.PeerSupervisorTest do
  use ExUnit.Case, async: false

  alias Kerto.Mesh.{Peer, PeerSupervisor}

  @engine :test_ps_engine

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    sup = start_supervised!({PeerSupervisor, name: :test_peer_sup})
    %{sup: sup}
  end

  describe "start_peer/2" do
    test "starts a peer process", %{sup: sup} do
      opts = [
        name: :test_ps_peer_a,
        peer_node: "kerto@dev-b",
        engine: @engine,
        peer_ref: self()
      ]

      assert {:ok, pid} = PeerSupervisor.start_peer(sup, opts)
      assert is_pid(pid)
      assert %{status: :idle} = Peer.status(:test_ps_peer_a)
    end

    test "handles already started peer", %{sup: sup} do
      opts = [
        name: :test_ps_peer_dup,
        peer_node: "kerto@dev-b",
        engine: @engine,
        peer_ref: self()
      ]

      {:ok, pid1} = PeerSupervisor.start_peer(sup, opts)
      {:ok, pid2} = PeerSupervisor.start_peer(sup, opts)
      assert pid1 == pid2
    end
  end

  describe "stop_peer/2" do
    test "stops a running peer", %{sup: sup} do
      opts = [
        name: :test_ps_peer_stop,
        peer_node: "kerto@dev-c",
        engine: @engine,
        peer_ref: self()
      ]

      {:ok, _pid} = PeerSupervisor.start_peer(sup, opts)
      assert :ok = PeerSupervisor.stop_peer(sup, :test_ps_peer_stop)
    end

    test "returns error for unknown peer", %{sup: sup} do
      assert {:error, :not_found} = PeerSupervisor.stop_peer(sup, :nonexistent_peer)
    end
  end

  describe "connected_peers/1" do
    test "lists connected peer pids", %{sup: sup} do
      opts1 = [name: :test_ps_list_a, peer_node: "a@x", engine: @engine, peer_ref: self()]
      opts2 = [name: :test_ps_list_b, peer_node: "b@x", engine: @engine, peer_ref: self()]

      {:ok, pid1} = PeerSupervisor.start_peer(sup, opts1)
      {:ok, pid2} = PeerSupervisor.start_peer(sup, opts2)

      peers = PeerSupervisor.connected_peers(sup)
      assert pid1 in peers
      assert pid2 in peers
    end

    test "returns empty list when no peers", %{sup: sup} do
      assert PeerSupervisor.connected_peers(sup) == []
    end
  end
end
