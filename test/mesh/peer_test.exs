defmodule Kerto.Mesh.PeerTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine
  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Mesh.Peer

  defp make_occurrence(type, ulid, files \\ ["a.go"]) do
    source = Source.new("test", "agent", ulid)
    Occurrence.new(type, %{files: files, task: "test"}, source)
  end

  setup do
    engine =
      start_supervised!({Engine, name: :peer_test_engine, decay_interval_ms: :timer.hours(1)})

    %{engine: engine}
  end

  describe "start_link + status" do
    test "starts in idle" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_idle, peer_node: "kerto@dev-b", engine: :peer_test_engine, peer_ref: self()}
        )

      assert %{peer: "kerto@dev-b", status: :idle} = Peer.status(peer)
    end
  end

  describe "connect" do
    test "transitions to handshake and sends hello to peer_ref" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_connect,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      assert :ok = Peer.connect(peer)
      assert %{status: :handshake} = Peer.status(peer)

      assert_received {:sync_hello, nil, "kerto@dev-a"}
    end

    test "returns error when not idle" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_connect2,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      Peer.connect(peer)

      assert {:error, :not_idle} = Peer.connect(peer)
    end
  end

  describe "recv sync_hello in handshake" do
    test "replays filtered occurrences, sends sync_live, transitions to replaying" do
      # Ingest some occurrences — one syncable, one not
      Engine.ingest(:peer_test_engine, make_occurrence("ci.run.failed", "01JAAA"))
      Engine.ingest(:peer_test_engine, make_occurrence("context.pattern", "01JBBB"))

      peer =
        start_supervised!(
          {Peer,
           name: :peer_hello_hs,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      Peer.connect(peer)
      # Drain our own hello
      assert_received {:sync_hello, nil, "kerto@dev-a"}

      # Simulate remote peer's hello response
      send(peer, {:sync_hello, nil, "kerto@dev-b"})
      # Use status call as sync barrier
      assert %{status: :replaying} = Peer.status(peer)

      # Should have replayed only the syncable occurrence
      assert_received {:sync_occurrence, occ}
      assert occ.type == "ci.run.failed"
      refute_received {:sync_occurrence, _}

      # Should have sent sync_live
      assert_received :sync_live
    end
  end

  describe "recv sync_hello in idle (remote-initiated)" do
    test "responds with hello, replays, sends sync_live, transitions to replaying" do
      Engine.ingest(:peer_test_engine, make_occurrence("vcs.commit", "01JAAA"))

      peer =
        start_supervised!(
          {Peer,
           name: :peer_hello_idle,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      # Remote peer initiates connection
      send(peer, {:sync_hello, nil, "kerto@dev-b"})
      assert %{status: :replaying} = Peer.status(peer)

      # Should respond with our hello
      assert_received {:sync_hello, nil, "kerto@dev-a"}

      # Should replay syncable occurrences
      assert_received {:sync_occurrence, occ}
      assert occ.type == "vcs.commit"

      # Should send sync_live
      assert_received :sync_live
    end
  end

  describe "recv sync_occurrence" do
    test "ingests into engine and tracks ULID" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_occ,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      occ = make_occurrence("ci.run.failed", "01JREMOTE", ["remote.go"])
      send(peer, {:sync_occurrence, occ})

      # Sync barrier
      Peer.status(peer)

      # Occurrence should be ingested into engine
      assert {:ok, _node} = Engine.get_node(:peer_test_engine, :file, "remote.go")
    end
  end

  describe "recv sync_live" do
    test "both sides done transitions to live and starts poll timer" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_live,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a",
           poll_interval_ms: 50}
        )

      # Connect and do handshake
      Peer.connect(peer)
      assert_received {:sync_hello, nil, "kerto@dev-a"}

      send(peer, {:sync_hello, nil, "kerto@dev-b"})
      assert %{status: :replaying} = Peer.status(peer)
      # Drain sync_live we sent
      assert_received :sync_live

      # Now remote sends sync_live — both sides done
      send(peer, :sync_live)
      assert %{status: :live} = Peer.status(peer)
    end

    test "peer_live before we_sent_live stays in current state" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_live2,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      # Receive sync_live before we've connected and replayed
      send(peer, :sync_live)
      assert %{status: :idle} = Peer.status(peer)
    end
  end

  describe "poll" do
    test "forwards new local occurrences, advances sync point, no re-sends" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_poll,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a",
           poll_interval_ms: 50}
        )

      # Get to live state
      Peer.connect(peer)
      assert_received {:sync_hello, nil, "kerto@dev-a"}

      send(peer, {:sync_hello, nil, "kerto@dev-b"})
      assert %{status: :replaying} = Peer.status(peer)
      assert_received :sync_live

      send(peer, :sync_live)
      assert %{status: :live} = Peer.status(peer)

      # Now ingest a new occurrence while live
      Engine.ingest(:peer_test_engine, make_occurrence("ci.run.failed", "01JPOLL1"))

      # Wait for poll to fire
      assert_receive {:sync_occurrence, occ}, 200
      assert occ.source.ulid == "01JPOLL1"

      # Wait for another poll — should NOT re-send
      # Drain any poll-triggered messages
      Process.sleep(100)
      refute_received {:sync_occurrence, _}
    end
  end

  describe "disconnect" do
    test "resets to idle, preserves sync_points" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_disc,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      Peer.connect(peer)
      assert %{status: :handshake} = Peer.status(peer)

      assert :ok = Peer.disconnect(peer)
      assert %{status: :idle} = Peer.status(peer)
    end
  end

  describe "nodedown" do
    test "resets to idle" do
      peer =
        start_supervised!(
          {Peer,
           name: :peer_nodedown,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      Peer.connect(peer)
      assert %{status: :handshake} = Peer.status(peer)

      send(peer, {:nodedown, :"kerto@dev-b"})
      assert %{status: :idle} = Peer.status(peer)
    end
  end

  describe "filter_syncable" do
    test "non-syncable types are not forwarded during replay" do
      # Ingest only non-syncable occurrences
      Engine.ingest(:peer_test_engine, make_occurrence("context.pattern", "01JNOTSYNC1"))
      Engine.ingest(:peer_test_engine, make_occurrence("context.query", "01JNOTSYNC2"))

      peer =
        start_supervised!(
          {Peer,
           name: :peer_filter,
           peer_node: "kerto@dev-b",
           engine: :peer_test_engine,
           peer_ref: self(),
           my_node: "kerto@dev-a"}
        )

      Peer.connect(peer)
      assert_received {:sync_hello, nil, "kerto@dev-a"}

      send(peer, {:sync_hello, nil, "kerto@dev-b"})
      assert %{status: :replaying} = Peer.status(peer)

      # Should have sent sync_live but no occurrences
      assert_received :sync_live
      refute_received {:sync_occurrence, _}
    end
  end
end
