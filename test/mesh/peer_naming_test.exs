defmodule Kerto.Mesh.PeerNamingTest do
  use ExUnit.Case, async: true

  alias Kerto.Mesh.PeerNaming

  describe "process_name/1" do
    test "returns atom for valid name@host" do
      assert {:ok, :"kerto.peer.kerto@dev-b.local"} =
               PeerNaming.process_name("kerto@dev-b.local")
    end

    test "rejects strings without @" do
      assert {:error, :invalid_peer_node} = PeerNaming.process_name("no-at-sign")
    end

    test "rejects empty string" do
      assert {:error, :invalid_peer_node} = PeerNaming.process_name("")
    end

    test "rejects strings with spaces" do
      assert {:error, :invalid_peer_node} = PeerNaming.process_name("bad name@host")
    end

    test "rejects strings with special characters" do
      assert {:error, :invalid_peer_node} = PeerNaming.process_name("bad;drop@host")
    end

    test "accepts underscores, hyphens, dots" do
      assert {:ok, _} = PeerNaming.process_name("kerto_v2@dev-b.local")
    end
  end

  describe "peer_ref/1" do
    test "returns {Peer, atom} tuple for valid peer" do
      assert {:ok, {Kerto.Mesh.Peer, :"kerto@dev-b"}} =
               PeerNaming.peer_ref("kerto@dev-b")
    end

    test "rejects invalid peer node" do
      assert {:error, :invalid_peer_node} = PeerNaming.peer_ref("invalid string!")
    end
  end

  describe "valid_peer_node?/1" do
    test "valid format" do
      assert PeerNaming.valid_peer_node?("kerto@dev-b.local")
      assert PeerNaming.valid_peer_node?("node1@192.168.1.1")
    end

    test "rejects too-long strings" do
      long = String.duplicate("a", 200) <> "@" <> String.duplicate("b", 200)
      refute PeerNaming.valid_peer_node?(long)
    end

    test "rejects non-strings" do
      refute PeerNaming.valid_peer_node?(123)
      refute PeerNaming.valid_peer_node?(nil)
    end
  end
end
