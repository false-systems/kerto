defmodule Kerto.Mesh.AuthorityTest do
  use ExUnit.Case, async: true

  alias Kerto.Mesh.{Authority, Identity}

  describe "init_ca/1" do
    test "creates a CA key and self-signed certificate" do
      {ca_key, ca_cert} = Authority.init_ca("test-team")
      assert is_tuple(ca_key)
      assert elem(ca_key, 0) == :ECPrivateKey
      assert is_tuple(ca_cert)
    end

    test "CA certificate is self-signed (issuer == subject)" do
      {_key, cert} = Authority.init_ca("my-team")
      # The subject and issuer should both contain the team name
      subject = X509.Certificate.subject(cert)
      issuer = X509.Certificate.issuer(cert)
      assert subject == issuer
    end

    test "CA certificate has the team name in CN" do
      {_key, cert} = Authority.init_ca("false-systems")
      subject = X509.Certificate.subject(cert) |> X509.RDNSequence.to_string()
      assert subject =~ "false-systems"
    end
  end

  describe "create_csr/2" do
    test "creates a CSR with the given name" do
      key = Identity.generate_key()
      csr = Authority.create_csr(key, "dev-a")
      assert is_tuple(csr)
    end

    test "CSR contains the node name" do
      key = Identity.generate_key()
      csr = Authority.create_csr(key, "dev-a")
      subject = X509.CSR.subject(csr) |> X509.RDNSequence.to_string()
      assert subject =~ "dev-a"
    end
  end

  describe "sign_csr/4" do
    test "produces a valid certificate" do
      {ca_key, ca_cert} = Authority.init_ca("team")
      node_key = Identity.generate_key()
      csr = Authority.create_csr(node_key, "dev-a")

      node_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)
      assert is_tuple(node_cert)
    end

    test "signed cert is issued by the CA" do
      {ca_key, ca_cert} = Authority.init_ca("team")
      node_key = Identity.generate_key()
      csr = Authority.create_csr(node_key, "dev-a")

      node_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)
      issuer = X509.Certificate.issuer(node_cert) |> X509.RDNSequence.to_string()
      assert issuer =~ "team"
    end

    test "signed cert preserves the CSR subject" do
      {ca_key, ca_cert} = Authority.init_ca("team")
      node_key = Identity.generate_key()
      csr = Authority.create_csr(node_key, "dev-a")

      node_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)
      subject = X509.Certificate.subject(node_cert) |> X509.RDNSequence.to_string()
      assert subject =~ "dev-a"
    end
  end

  describe "verify/2" do
    test "returns true for a cert signed by the CA" do
      {ca_key, ca_cert} = Authority.init_ca("team")
      node_key = Identity.generate_key()
      csr = Authority.create_csr(node_key, "dev-a")
      node_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)

      assert Authority.verify(node_cert, ca_cert) == true
    end

    test "returns false for a cert signed by a different CA" do
      {ca_key, ca_cert} = Authority.init_ca("team-a")
      {_other_key, other_ca} = Authority.init_ca("team-b")

      node_key = Identity.generate_key()
      csr = Authority.create_csr(node_key, "dev-a")
      node_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)

      assert Authority.verify(node_cert, other_ca) == false
    end

    test "CA cert verifies against itself" do
      {_key, ca_cert} = Authority.init_ca("team")
      assert Authority.verify(ca_cert, ca_cert) == true
    end
  end

  describe "full workflow" do
    test "team init → join → sign → verify" do
      # Team lead creates CA
      {ca_key, ca_cert} = Authority.init_ca("false-systems")

      # Developer generates key and CSR
      dev_key = Identity.generate_key()
      csr = Authority.create_csr(dev_key, "yair-macbook")

      # Team lead signs
      dev_cert = Authority.sign_csr(ca_key, ca_cert, csr, 365)

      # Verification passes
      assert Authority.verify(dev_cert, ca_cert)

      # Both certs share the same team fingerprint context
      ca_fp = Identity.short_fingerprint(ca_cert)
      assert String.length(ca_fp) == 8

      # Dev cert has different fingerprint from CA
      dev_fp = Identity.fingerprint(dev_cert)
      ca_full_fp = Identity.fingerprint(ca_cert)
      refute dev_fp == ca_full_fp
    end
  end
end
