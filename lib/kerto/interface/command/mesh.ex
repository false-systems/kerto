defmodule Kerto.Interface.Command.Mesh do
  @moduledoc """
  Mesh network management — start, stop, status, connect, add/remove peers.

  Subcommands via --action flag:
    status      — show mesh status (connected peers, sync state)
    connect     — connect to a specific peer
    add-peer    — add a peer to the discovery list
    remove-peer — remove a peer from the discovery list
  """

  alias Kerto.Interface.Response
  alias Kerto.Mesh.PeerNaming

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    case Map.get(args, :action) do
      "status" -> mesh_status(engine)
      "connect" -> connect_peer(engine, args)
      "add-peer" -> add_peer(engine, args)
      "remove-peer" -> remove_peer(engine, args)
      nil -> Response.error("specify --action: status, connect, add-peer, or remove-peer")
      other -> Response.error("unknown mesh action: #{other}")
    end
  end

  defp mesh_status(engine) do
    discovery = discovery_name(engine)

    peers =
      try do
        Kerto.Mesh.Discovery.known_peers(discovery)
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    if peers == [] do
      Response.success("Mesh: no peers configured")
    else
      header = "Mesh: #{length(peers)} peer(s)\n"
      list = Enum.map_join(peers, "\n", &"  #{&1}")
      Response.success(header <> list)
    end
  end

  defp connect_peer(engine, args) do
    peer_node = Map.get(args, :peer)

    if is_nil(peer_node) do
      Response.error("specify --peer <node@host>")
    else
      with {:ok, peer_name} <- PeerNaming.process_name(peer_node),
           {:ok, peer_ref} <- PeerNaming.peer_ref(peer_node) do
        peer_supervisor = peer_supervisor_name(engine)

        peer_opts = [
          name: peer_name,
          peer_node: peer_node,
          engine: engine,
          peer_ref: peer_ref
        ]

        case Kerto.Mesh.PeerSupervisor.start_peer(peer_supervisor, peer_opts) do
          {:ok, _pid} ->
            Kerto.Mesh.Peer.connect(peer_name)
            Response.success("connecting to #{peer_node}")

          {:error, reason} ->
            Response.error("failed to start peer: #{inspect(reason)}")
        end
      else
        {:error, :invalid_peer_node} ->
          Response.error("invalid peer node format: #{peer_node} (expected name@host)")
      end
    end
  end

  defp add_peer(engine, args) do
    peer_node = Map.get(args, :peer)

    if is_nil(peer_node) do
      Response.error("specify --peer <node@host>")
    else
      Kerto.Mesh.Discovery.add_peer(discovery_name(engine), peer_node)
      Response.success("added peer: #{peer_node}")
    end
  end

  defp remove_peer(engine, args) do
    peer_node = Map.get(args, :peer)

    if is_nil(peer_node) do
      Response.error("specify --peer <node@host>")
    else
      Kerto.Mesh.Discovery.remove_peer(discovery_name(engine), peer_node)
      Response.success("removed peer: #{peer_node}")
    end
  end

  defp discovery_name(engine), do: :"#{engine}.discovery"
  defp peer_supervisor_name(engine), do: :"#{engine}.peer_supervisor"
end
