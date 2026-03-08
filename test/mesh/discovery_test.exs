defmodule Kerto.Mesh.DiscoveryTest do
  use ExUnit.Case, async: false

  alias Kerto.Mesh.{Discovery, PeerSupervisor}

  @engine :test_discovery_engine

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    sup = start_supervised!({PeerSupervisor, name: :test_disc_sup})

    discovery =
      start_supervised!(
        {Discovery,
         name: :test_discovery, engine: @engine, peer_supervisor: sup, poll_interval_ms: :infinity}
      )

    %{discovery: discovery, sup: sup}
  end

  describe "add_peer/2 and known_peers/1" do
    test "adds a peer to the list", %{discovery: discovery} do
      Discovery.add_peer(discovery, "kerto@dev-b.local")
      assert "kerto@dev-b.local" in Discovery.known_peers(discovery)
    end

    test "starts with empty peer list", %{discovery: discovery} do
      assert Discovery.known_peers(discovery) == []
    end
  end

  describe "remove_peer/2" do
    test "removes a peer from the list", %{discovery: discovery} do
      Discovery.add_peer(discovery, "kerto@dev-b.local")
      Discovery.remove_peer(discovery, "kerto@dev-b.local")
      refute "kerto@dev-b.local" in Discovery.known_peers(discovery)
    end
  end

  describe "peers.conf loading" do
    test "loads peers from config file" do
      path = Path.join(System.tmp_dir!(), "test_peers_#{System.unique_integer([:positive])}.conf")

      File.write!(path, """
      # Comment line
      kerto@dev-a.local
      kerto@dev-b.local

      # Another comment
      kerto@build.internal
      """)

      disc =
        start_supervised!(
          {Discovery,
           name: :"test_disc_conf_#{System.unique_integer([:positive])}",
           engine: @engine,
           peer_supervisor: :test_disc_sup,
           peers_conf: path,
           poll_interval_ms: :infinity},
          id: :conf_disc
        )

      peers = Discovery.known_peers(disc)
      assert "kerto@dev-a.local" in peers
      assert "kerto@dev-b.local" in peers
      assert "kerto@build.internal" in peers
      assert length(peers) == 3

      File.rm!(path)
    end

    test "handles missing config file gracefully" do
      disc =
        start_supervised!(
          {Discovery,
           name: :"test_disc_missing_#{System.unique_integer([:positive])}",
           engine: @engine,
           peer_supervisor: :test_disc_sup,
           peers_conf: "/nonexistent/path",
           poll_interval_ms: :infinity},
          id: :missing_disc
        )

      assert Discovery.known_peers(disc) == []
    end
  end
end
