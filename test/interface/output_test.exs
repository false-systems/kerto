defmodule Kerto.Interface.OutputTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.{Output, Response}

  import ExUnit.CaptureIO

  describe "format/2 text mode" do
    test "formats success with string data" do
      resp = Response.success("auth.go (file) — relevance 0.82")
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "auth.go (file)"
    end

    test "formats success with :ok data" do
      resp = Response.success(:ok)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "OK"
    end

    test "formats success with status map" do
      resp = Response.success(%{nodes: 5, relationships: 3, occurrences: 12})
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "5"
      assert output =~ "3"
      assert output =~ "12"
    end

    test "formats error with string" do
      resp = Response.error("missing required argument: name")
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "Error"
      assert output =~ "missing required argument: name"
    end

    test "formats error with atom" do
      resp = Response.error(:not_found)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "not_found"
    end

    test "formats success with graph data" do
      graph_data = %{
        nodes: [%{name: "auth.go", kind: :file, relevance: 0.8, observations: 5}],
        relationships: [%{source: "a1", target: "b2", relation: :breaks, weight: 0.7}]
      }

      resp = Response.success(graph_data)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "auth.go"
    end
  end

  describe "format/2 json mode" do
    test "formats success as JSON" do
      resp = Response.success(%{nodes: 3, relationships: 1, occurrences: 10})
      output = capture_io(fn -> Output.print(resp, :json) end)
      decoded = Jason.decode!(output)
      assert decoded["ok"] == true
      assert decoded["data"]["nodes"] == 3
    end

    test "formats error as JSON" do
      resp = Response.error("something broke")
      output = capture_io(fn -> Output.print(resp, :json) end)
      decoded = Jason.decode!(output)
      assert decoded["ok"] == false
      assert decoded["error"] == "something broke"
    end

    test "formats atom values as strings in JSON" do
      resp = Response.success(:ok)
      output = capture_io(fn -> Output.print(resp, :json) end)
      decoded = Jason.decode!(output)
      assert decoded["data"] == "ok"
    end

    test "formats atom error as string in JSON" do
      resp = Response.error(:not_found)
      output = capture_io(fn -> Output.print(resp, :json) end)
      decoded = Jason.decode!(output)
      assert decoded["error"] == "not_found"
    end
  end
end
