defmodule Kerto.Mesh.TransportTest do
  use ExUnit.Case, async: true

  alias Kerto.Mesh.Transport

  @paths %{
    node_cert: "/home/dev/.kerto/node.crt",
    node_key: "/home/dev/.kerto/node.key",
    ca_cert: "/home/dev/.kerto/ca.crt"
  }

  describe "ssl_dist_config/1" do
    test "generates valid Erlang term format" do
      config = Transport.ssl_dist_config(@paths)
      assert is_binary(config)
      assert config =~ "server"
      assert config =~ "client"
    end

    test "includes certificate paths" do
      config = Transport.ssl_dist_config(@paths)
      assert config =~ "/home/dev/.kerto/node.crt"
      assert config =~ "/home/dev/.kerto/node.key"
      assert config =~ "/home/dev/.kerto/ca.crt"
    end

    test "requires peer verification" do
      config = Transport.ssl_dist_config(@paths)
      assert config =~ "verify_peer"
      assert config =~ "fail_if_no_peer_cert"
    end

    test "uses TLS 1.3 only" do
      config = Transport.ssl_dist_config(@paths)
      assert config =~ "tlsv1.3"
    end

    test "includes both server and client sections" do
      config = Transport.ssl_dist_config(@paths)
      assert config =~ "{server,"
      assert config =~ "{client,"
    end
  end

  describe "vm_args/1" do
    test "generates BEAM distribution flags" do
      args = Transport.vm_args("kerto@dev-a", "/tmp/ssl_dist.conf")
      assert is_list(args)
      assert "-proto_dist" in args
      assert "inet_tls" in args
    end

    test "includes ssl_dist_optfile flag" do
      args = Transport.vm_args("kerto@dev-a", "/tmp/ssl_dist.conf")
      assert "-ssl_dist_optfile" in args
      assert "/tmp/ssl_dist.conf" in args
    end

    test "includes node name" do
      args = Transport.vm_args("kerto@dev-a", "/tmp/ssl_dist.conf")
      assert "-name" in args
      assert "kerto@dev-a" in args
    end
  end
end
