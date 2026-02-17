defmodule Kerto.Mesh.Identity do
  @moduledoc """
  Cryptographic identity for mesh nodes.

  ECDSA P-256 keys for TLS mutual authentication.
  Fingerprints for team discovery matching.
  """

  @curve :secp256r1

  @spec generate_key() :: X509.PrivateKey.t()
  def generate_key do
    X509.PrivateKey.new_ec(@curve)
  end

  @spec key_to_pem(X509.PrivateKey.t()) :: String.t()
  def key_to_pem(key) do
    X509.PrivateKey.to_pem(key)
  end

  @spec key_from_pem(String.t()) :: X509.PrivateKey.t()
  def key_from_pem(pem) when is_binary(pem) do
    X509.PrivateKey.from_pem!(pem)
  end

  @spec cert_to_pem(X509.Certificate.t()) :: String.t()
  def cert_to_pem(cert) do
    X509.Certificate.to_pem(cert)
  end

  @spec cert_from_pem(String.t()) :: X509.Certificate.t()
  def cert_from_pem(pem) when is_binary(pem) do
    X509.Certificate.from_pem!(pem)
  end

  @spec fingerprint(X509.Certificate.t()) :: String.t()
  def fingerprint(cert) do
    cert
    |> X509.Certificate.to_der()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec short_fingerprint(X509.Certificate.t()) :: String.t()
  def short_fingerprint(cert) do
    cert
    |> fingerprint()
    |> String.slice(0, 8)
  end
end
