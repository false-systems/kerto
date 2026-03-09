defmodule Kerto.Interface.Command.MeshTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Mesh
  alias Kerto.Mesh.{Discovery, PeerSupervisor}

  @engine :test_mesh_cmd_engine

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    start_supervised!({PeerSupervisor, name: :"#{@engine}.peer_supervisor"})

    start_supervised!(
      {Discovery,
       name: :"#{@engine}.discovery",
       engine: @engine,
       peer_supervisor: :"#{@engine}.peer_supervisor",
       poll_interval_ms: :infinity}
    )

    :ok
  end

  describe "status action" do
    test "shows no peers initially" do
      resp = Mesh.execute(@engine, %{action: "status"})
      assert resp.ok
      assert resp.data =~ "no peers"
    end

    test "shows peers after adding" do
      Discovery.add_peer(:"#{@engine}.discovery", "kerto@dev-b")
      resp = Mesh.execute(@engine, %{action: "status"})
      assert resp.ok
      assert resp.data =~ "kerto@dev-b"
    end
  end

  describe "add-peer action" do
    test "adds a peer" do
      resp = Mesh.execute(@engine, %{action: "add-peer", peer: "kerto@dev-b"})
      assert resp.ok
      assert resp.data =~ "added peer"
    end

    test "returns error without peer name" do
      resp = Mesh.execute(@engine, %{action: "add-peer"})
      refute resp.ok
      assert resp.error =~ "--peer"
    end
  end

  describe "remove-peer action" do
    test "removes a peer" do
      Discovery.add_peer(:"#{@engine}.discovery", "kerto@dev-b")
      resp = Mesh.execute(@engine, %{action: "remove-peer", peer: "kerto@dev-b"})
      assert resp.ok
      assert resp.data =~ "removed peer"
    end
  end

  describe "missing action" do
    test "returns error" do
      resp = Mesh.execute(@engine, %{})
      refute resp.ok
      assert resp.error =~ "specify --action"
    end
  end
end
