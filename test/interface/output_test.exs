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

    test "formats success with node list data" do
      node_data = %{
        nodes: [
          %{name: "auth.go", kind: "file", relevance: 0.8, observations: 5, pinned: false}
        ]
      }

      resp = Response.success(node_data)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "auth.go"
      assert output =~ "1 node(s)"
    end

    test "formats success with relationship list data" do
      rel_data = %{
        relationships: [
          %{
            source: "a1",
            target: "b2",
            source_name: "auth.go",
            target_name: "test.go",
            relation: "breaks",
            weight: 0.7,
            observations: 1,
            pinned: false
          }
        ]
      }

      resp = Response.success(rel_data)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "auth.go"
      assert output =~ "breaks"
      assert output =~ "1 relationship(s)"
    end

    test "formats success with context data" do
      ctx_data = %{
        node: %{name: "auth.go", kind: "file"},
        relationships: [],
        rendered: "auth.go (file) — relevance 0.80"
      }

      resp = Response.success(ctx_data)
      output = capture_io(fn -> Output.print(resp, :text) end)
      assert output =~ "auth.go (file)"
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

    test "preserves booleans and nil in JSON output" do
      resp =
        Response.success(%{
          nodes: [%{name: "auth.go", kind: :file, pinned: false, summary: nil}]
        })

      output = capture_io(fn -> Output.print(resp, :json) end)
      decoded = Jason.decode!(output)
      node = hd(decoded["data"]["nodes"])
      assert node["pinned"] == false
      assert node["summary"] == nil
      assert node["kind"] == "file"
    end
  end
end
