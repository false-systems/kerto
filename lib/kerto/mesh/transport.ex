defmodule Kerto.Mesh.Transport do
  @moduledoc """
  Generates BEAM TLS distribution configuration.

  Produces the `ssl_dist.conf` file that Erlang reads to enable
  mutual TLS on BEAM distribution. Both server and client require
  peer certificate verification against the team CA.
  """

  @spec ssl_dist_config(%{node_cert: String.t(), node_key: String.t(), ca_cert: String.t()}) ::
          String.t()
  def ssl_dist_config(%{node_cert: cert, node_key: key, ca_cert: ca}) do
    """
    [{server, [
      {certfile, "#{cert}"},
      {keyfile, "#{key}"},
      {cacertfile, "#{ca}"},
      {verify, verify_peer},
      {fail_if_no_peer_cert, true},
      {secure_renegotiate, true},
      {versions, ['tlsv1.3']}
    ]},
    {client, [
      {certfile, "#{cert}"},
      {keyfile, "#{key}"},
      {cacertfile, "#{ca}"},
      {verify, verify_peer},
      {secure_renegotiate, true},
      {versions, ['tlsv1.3']}
    ]}].
    """
  end

  @spec vm_args(String.t(), String.t()) :: [String.t()]
  def vm_args(node_name, ssl_dist_conf_path) do
    [
      "-name",
      node_name,
      "-proto_dist",
      "inet_tls",
      "-ssl_dist_optfile",
      ssl_dist_conf_path
    ]
  end
end
