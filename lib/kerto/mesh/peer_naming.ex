defmodule Kerto.Mesh.PeerNaming do
  @moduledoc """
  Safe peer name handling for mesh networking.

  Validates peer node strings and converts to atoms safely,
  avoiding unbounded `String.to_atom/1` on user input.
  """

  @peer_node_pattern ~r/^[a-zA-Z0-9_\-\.]+@[a-zA-Z0-9_\-\.]+$/

  @spec process_name(String.t()) :: {:ok, atom()} | {:error, :invalid_peer_node}
  def process_name(peer_node) when is_binary(peer_node) do
    if valid_peer_node?(peer_node) do
      {:ok, :"kerto.peer.#{peer_node}"}
    else
      {:error, :invalid_peer_node}
    end
  end

  @spec peer_ref(String.t()) :: {:ok, {module(), atom()}} | {:error, :invalid_peer_node}
  def peer_ref(peer_node) when is_binary(peer_node) do
    if valid_peer_node?(peer_node) do
      {:ok, {Kerto.Mesh.Peer, String.to_atom(peer_node)}}
    else
      {:error, :invalid_peer_node}
    end
  end

  @spec valid_peer_node?(String.t()) :: boolean()
  def valid_peer_node?(peer_node) when is_binary(peer_node) do
    Regex.match?(@peer_node_pattern, peer_node) and byte_size(peer_node) <= 255
  end

  def valid_peer_node?(_), do: false
end
