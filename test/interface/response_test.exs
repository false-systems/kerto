defmodule Kerto.Interface.ResponseTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.Response

  describe "success/1" do
    test "creates ok response with data" do
      resp = Response.success(%{nodes: 5})
      assert resp.ok == true
      assert resp.data == %{nodes: 5}
      assert resp.error == nil
    end

    test "works with string data" do
      resp = Response.success("auth.go (file) — relevance 0.82")
      assert resp.ok
      assert resp.data =~ "auth.go"
    end
  end

  describe "error/1" do
    test "creates error response" do
      resp = Response.error(:not_found)
      assert resp.ok == false
      assert resp.error == :not_found
      assert resp.data == nil
    end

    test "works with string errors" do
      resp = Response.error("missing --subject flag")
      refute resp.ok
      assert resp.error == "missing --subject flag"
    end
  end
end
