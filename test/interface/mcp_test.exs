defmodule Kerto.Interface.MCPTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.MCP
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    engine = :"test_mcp_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    %{engine: engine}
  end

  describe "handle_message/3 initialize" do
    test "returns server info and capabilities", %{engine: engine} do
      msg = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      result = MCP.handle_message(msg, engine, nil)
      assert result.id == 1
      assert result.result.serverInfo.name == "kerto"
      assert result.result.protocolVersion == "2024-11-05"
    end
  end

  describe "handle_message/3 tools/list" do
    test "returns all 6 tools", %{engine: engine} do
      msg = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
      result = MCP.handle_message(msg, engine, nil)
      tools = result.result.tools
      assert length(tools) == 6

      names = Enum.map(tools, & &1.name)
      assert "kerto_context" in names
      assert "kerto_learn" in names
      assert "kerto_status" in names
    end
  end

  describe "handle_message/3 tools/call" do
    test "dispatches kerto_status", %{engine: engine} do
      msg = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "kerto_status", "arguments" => %{}}
      }

      result = MCP.handle_message(msg, engine, nil)
      assert result.id == 3
      [content] = result.result.content
      assert content.type == "text"
      decoded = Jason.decode!(content.text)
      assert is_integer(decoded["nodes"])
    end

    test "dispatches kerto_learn and returns success", %{engine: engine} do
      msg = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "kerto_learn",
          "arguments" => %{
            "evidence" => "auth handles auth",
            "subject" => "auth.go",
            "subject_kind" => "file",
            "target" => "authentication",
            "target_kind" => "concept",
            "relation" => "learned"
          }
        }
      }

      result = MCP.handle_message(msg, engine, nil)
      [content] = result.result.content
      assert content.text == "OK"
      refute Map.has_key?(result.result, :isError)
    end

    test "returns error for unknown tool", %{engine: engine} do
      msg = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "kerto_explode", "arguments" => %{}}
      }

      result = MCP.handle_message(msg, engine, nil)
      assert result.result.isError == true
      [content] = result.result.content
      assert content.text =~ "unknown tool"
    end
  end

  describe "handle_message/3 error cases" do
    test "returns method not found for unknown method", %{engine: engine} do
      msg = %{"jsonrpc" => "2.0", "id" => 6, "method" => "unknown/method"}
      result = MCP.handle_message(msg, engine, nil)
      assert result.error.code == -32601
    end

    test "returns nil for notifications", %{engine: engine} do
      msg = %{"method" => "notifications/initialized"}
      assert MCP.handle_message(msg, engine, nil) == nil
    end
  end

  describe "dispatch_tool/3" do
    test "returns context for existing entity", %{engine: engine} do
      learn(engine, "auth.go handles auth", "auth.go")

      assert {:ok, text} =
               MCP.dispatch_tool(
                 "kerto_context",
                 %{"name" => "auth.go", "kind" => "file"},
                 engine
               )

      assert text =~ "auth.go"
    end

    test "returns error for missing entity", %{engine: engine} do
      assert {:error, msg} = MCP.dispatch_tool("kerto_context", %{"name" => "nope.go"}, engine)
      assert msg =~ "not found"
    end

    test "dispatches graph command", %{engine: engine} do
      assert {:ok, text} = MCP.dispatch_tool("kerto_graph", %{}, engine)
      decoded = Jason.decode!(text)
      assert is_map(decoded)
    end

    test "dispatches weaken with proper arg atomization", %{engine: engine} do
      learn_with_target(engine)

      args = %{
        "source" => "auth.go",
        "source_kind" => "file",
        "relation" => "learned",
        "target" => "sessions",
        "target_kind" => "concept"
      }

      result = MCP.dispatch_tool("kerto_weaken", args, engine)
      assert {:ok, _} = result
    end
  end

  describe "context writer notification" do
    test "notifies context writer on mutating tool call", %{engine: engine} do
      test_dir =
        System.tmp_dir!() |> Path.join("kerto_mcp_cw_#{System.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)
      cw_path = Path.join(test_dir, "CONTEXT.md")

      cw =
        start_supervised!(
          {Kerto.Interface.ContextWriter,
           engine: engine,
           path: cw_path,
           debounce_ms: 10,
           name: :"test_mcp_cw_#{System.unique_integer([:positive])}"},
          id: :mcp_cw
        )

      msg = %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "tools/call",
        "params" => %{
          "name" => "kerto_learn",
          "arguments" => %{
            "evidence" => "mcp test",
            "subject" => "mcp.go",
            "subject_kind" => "file",
            "target" => "test",
            "target_kind" => "concept",
            "relation" => "learned"
          }
        }
      }

      MCP.handle_message(msg, engine, cw)
      Process.sleep(50)
      assert File.exists?(cw_path)
      assert File.read!(cw_path) =~ "mcp.go"
    end
  end

  defp learn(engine, evidence, subject) do
    occ =
      Occurrence.new(
        "context.learning",
        %{
          subject_kind: :file,
          subject_name: subject,
          target_kind: :concept,
          target_name: "knowledge",
          relation: :learned,
          evidence: evidence
        },
        Source.new("test", "test", Kerto.Interface.ULID.generate())
      )

    Kerto.Engine.ingest(engine, occ)
  end

  defp learn_with_target(engine) do
    occ =
      Occurrence.new(
        "context.learning",
        %{
          subject_kind: :file,
          subject_name: "auth.go",
          target_kind: :concept,
          target_name: "sessions",
          relation: :learned,
          evidence: "auth uses sessions"
        },
        Source.new("test", "test", Kerto.Interface.ULID.generate())
      )

    Kerto.Engine.ingest(engine, occ)
  end
end
