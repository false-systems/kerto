defmodule Kerto.Mesh.IdentityTest do
  use ExUnit.Case, async: true

  alias Kerto.Mesh.Identity

  describe "generate_key/0" do
    test "generates an EC private key" do
      key = Identity.generate_key()
      assert is_tuple(key)
      # x509 returns an ECPrivateKey record
      assert elem(key, 0) == :ECPrivateKey
    end

    test "generates unique keys each time" do
      key1 = Identity.generate_key()
      key2 = Identity.generate_key()
      refute key1 == key2
    end
  end

  describe "key_to_pem/1 and key_from_pem/1" do
    test "round-trips a private key through PEM" do
      key = Identity.generate_key()
      pem = Identity.key_to_pem(key)
      assert is_binary(pem)
      assert pem =~ "BEGIN EC PRIVATE KEY"

      decoded = Identity.key_from_pem(pem)
      assert decoded == key
    end
  end

  describe "cert_to_pem/1 and cert_from_pem/1" do
    test "round-trips a certificate through PEM" do
      key = Identity.generate_key()
      cert = X509.Certificate.self_signed(key, "/CN=test", validity: 365)
      pem = Identity.cert_to_pem(cert)

      assert is_binary(pem)
      assert pem =~ "BEGIN CERTIFICATE"

      decoded = Identity.cert_from_pem(pem)
      assert decoded == cert
    end
  end

  describe "fingerprint/1" do
    test "returns hex-encoded SHA-256 fingerprint" do
      key = Identity.generate_key()
      cert = X509.Certificate.self_signed(key, "/CN=test", validity: 365)
      fp = Identity.fingerprint(cert)

      assert is_binary(fp)
      # SHA-256 = 32 bytes = 64 hex chars
      assert String.length(fp) == 64
      assert fp =~ ~r/^[0-9a-f]+$/
    end

    test "same cert produces same fingerprint" do
      key = Identity.generate_key()
      cert = X509.Certificate.self_signed(key, "/CN=test", validity: 365)

      assert Identity.fingerprint(cert) == Identity.fingerprint(cert)
    end

    test "different certs produce different fingerprints" do
      key1 = Identity.generate_key()
      key2 = Identity.generate_key()
      cert1 = X509.Certificate.self_signed(key1, "/CN=a", validity: 365)
      cert2 = X509.Certificate.self_signed(key2, "/CN=b", validity: 365)

      refute Identity.fingerprint(cert1) == Identity.fingerprint(cert2)
    end
  end

  describe "short_fingerprint/1" do
    test "returns first 8 characters of fingerprint" do
      key = Identity.generate_key()
      cert = X509.Certificate.self_signed(key, "/CN=test", validity: 365)
      short = Identity.short_fingerprint(cert)
      full = Identity.fingerprint(cert)

      assert String.length(short) == 8
      assert short == String.slice(full, 0, 8)
    end
  end
end
