defmodule Kerto.Mesh.Authority do
  @moduledoc """
  Team Certificate Authority for mesh authentication.

  Manages the trust chain: CA init, CSR signing, verification.
  The CA cert is the team's trust anchor — shared across all nodes.
  Node certs are signed by the CA and prove mesh membership.
  """

  alias Kerto.Mesh.Identity

  @ca_validity_days 3650
  @ca_extensions [
    basic_constraints: X509.Certificate.Extension.basic_constraints(true, 0),
    key_usage: X509.Certificate.Extension.key_usage([:keyCertSign, :cRLSign])
  ]

  @spec init_ca(String.t()) :: {X509.PrivateKey.t(), X509.Certificate.t()}
  def init_ca(team_name) when is_binary(team_name) do
    key = Identity.generate_key()

    cert =
      X509.Certificate.self_signed(
        key,
        "/CN=#{team_name}/O=kerto-mesh",
        validity: @ca_validity_days,
        extensions: @ca_extensions
      )

    {key, cert}
  end

  @spec create_csr(X509.PrivateKey.t(), String.t()) :: X509.CSR.t()
  def create_csr(key, node_name) when is_binary(node_name) do
    X509.CSR.new(key, "/CN=#{node_name}/O=kerto-node")
  end

  @spec sign_csr(X509.PrivateKey.t(), X509.Certificate.t(), X509.CSR.t(), pos_integer()) ::
          X509.Certificate.t()
  def sign_csr(ca_key, ca_cert, csr, validity_days) when is_integer(validity_days) do
    public_key = X509.CSR.public_key(csr)
    subject = X509.CSR.subject(csr)

    X509.Certificate.new(
      public_key,
      subject,
      ca_cert,
      ca_key,
      validity: validity_days
    )
  end

  @spec verify(X509.Certificate.t(), X509.Certificate.t()) :: boolean()
  def verify(cert, ca_cert) do
    ca_public_key = X509.Certificate.public_key(ca_cert)
    der = X509.Certificate.to_der(cert)
    :public_key.pkix_verify(der, ca_public_key)
  rescue
    _ -> false
  end
end
