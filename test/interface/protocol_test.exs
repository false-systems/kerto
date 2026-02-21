defmodule Kerto.Interface.ProtocolTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.{Protocol, Response}

  describe "encode_response/1" do
    test "encodes success response" do
      json = Protocol.encode_response(Response.success(%{nodes: 5}))
      decoded = Jason.decode!(json)
      assert decoded == %{"ok" => true, "data" => %{"nodes" => 5}}
    end

    test "encodes error response" do
      json = Protocol.encode_response(Response.error("not found"))
      decoded = Jason.decode!(json)
      assert decoded == %{"ok" => false, "error" => "not found"}
    end

    test "serializes atom data" do
      json = Protocol.encode_response(Response.success(:ok))
      decoded = Jason.decode!(json)
      assert decoded["data"] == "ok"
    end
  end

  describe "decode_request/1" do
    test "decodes command with args" do
      line = Jason.encode!(%{command: "learn", args: %{evidence: "test", subject: "auth.go"}})
      assert {"learn", %{evidence: "test", subject: "auth.go"}} = Protocol.decode_request(line)
    end

    test "decodes command without args" do
      line = Jason.encode!(%{command: "status"})
      assert {"status", %{}} = Protocol.decode_request(line)
    end

    test "atomizes known value fields" do
      line = Jason.encode!(%{command: "context", args: %{kind: "file", name: "auth.go"}})
      {"context", args} = Protocol.decode_request(line)
      assert args.kind == :file
      assert args.name == "auth.go"
    end

    test "returns error for missing command field" do
      line = Jason.encode!(%{args: %{}})
      assert {:error, "missing \"command\" field"} = Protocol.decode_request(line)
    end

    test "returns error for invalid JSON" do
      assert {:error, "invalid JSON"} = Protocol.decode_request("not json")
    end
  end
end
