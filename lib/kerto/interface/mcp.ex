defmodule Kerto.Interface.MCP do
  @moduledoc "MCP server over stdio (JSON-RPC 2.0, newline-delimited)."

  alias Kerto.Interface.{ContextWriter, Dispatcher, Protocol}

  @mutating_commands ~w(learn decide ingest decay weaken delete)

  @tools [
    %{
      name: "kerto_context",
      description: "Query an entity and render its knowledge context",
      inputSchema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Entity name (e.g. auth.go)"},
          kind: %{
            type: "string",
            description: "Node kind: file, module, pattern, decision, error, concept"
          },
          depth: %{type: "integer", description: "Traversal depth (default: 1)"},
          min_weight: %{type: "number", description: "Min relationship weight (default: 0.0)"}
        },
        required: ["name"]
      }
    },
    %{
      name: "kerto_learn",
      description: "Record a learning about the codebase",
      inputSchema: %{
        type: "object",
        properties: %{
          evidence: %{type: "string", description: "What was learned"},
          subject: %{type: "string", description: "Subject entity name"},
          subject_kind: %{type: "string", description: "Subject kind (default: file)"},
          target: %{type: "string", description: "Target entity name (optional)"},
          target_kind: %{type: "string", description: "Target kind (default: concept)"},
          relation: %{type: "string", description: "Relationship type (default: learned)"},
          confidence: %{type: "number", description: "Confidence 0.0-1.0 (default: 0.8)"}
        },
        required: ["evidence", "subject"]
      }
    },
    %{
      name: "kerto_decide",
      description: "Record an architectural decision",
      inputSchema: %{
        type: "object",
        properties: %{
          evidence: %{type: "string", description: "Decision description"},
          subject: %{type: "string", description: "Subject entity name"},
          subject_kind: %{type: "string", description: "Subject kind (default: decision)"},
          target: %{type: "string", description: "Target entity name (optional)"},
          target_kind: %{type: "string", description: "Target kind (default: file)"},
          confidence: %{type: "number", description: "Confidence 0.0-1.0 (default: 0.8)"}
        },
        required: ["evidence", "subject"]
      }
    },
    %{
      name: "kerto_status",
      description: "Show knowledge graph statistics",
      inputSchema: %{type: "object", properties: %{}}
    },
    %{
      name: "kerto_graph",
      description: "Dump the full knowledge graph",
      inputSchema: %{
        type: "object",
        properties: %{
          format: %{type: "string", description: "Output format: json or dot (default: json)"}
        }
      }
    },
    %{
      name: "kerto_weaken",
      description: "Weaken a specific relationship",
      inputSchema: %{
        type: "object",
        properties: %{
          source: %{type: "string", description: "Source entity name"},
          source_kind: %{type: "string", description: "Source kind (default: file)"},
          relation: %{type: "string", description: "Relationship type"},
          target: %{type: "string", description: "Target entity name"},
          target_kind: %{type: "string", description: "Target kind (default: file)"},
          factor: %{type: "number", description: "Weakening factor (default: 0.5)"}
        },
        required: ["source", "relation", "target"]
      }
    }
  ]

  @tool_to_command %{
    "kerto_context" => "context",
    "kerto_learn" => "learn",
    "kerto_decide" => "decide",
    "kerto_status" => "status",
    "kerto_graph" => "graph",
    "kerto_weaken" => "weaken"
  }

  @spec run(atom(), GenServer.server() | nil) :: no_return()
  def run(engine, context_writer \\ nil) do
    Logger.configure(level: :none)

    IO.stream(:stdio, :line)
    |> Enum.each(fn line ->
      case Jason.decode(String.trim(line)) do
        {:ok, message} ->
          response = handle_message(message, engine, context_writer)
          IO.write(Jason.encode!(response) <> "\n")

        {:error, _} ->
          error = jsonrpc_error(nil, -32700, "Parse error")
          IO.write(Jason.encode!(error) <> "\n")
      end
    end)
  end

  @spec handle_message(map(), atom(), GenServer.server() | nil) :: map()
  def handle_message(%{"method" => "initialize", "id" => id}, _engine, _cw) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{tools: %{}},
        serverInfo: %{name: "kerto", version: "0.1.0"}
      }
    }
  end

  def handle_message(%{"method" => "notifications/initialized"}, _engine, _cw) do
    nil
  end

  def handle_message(%{"method" => "tools/list", "id" => id}, _engine, _cw) do
    %{jsonrpc: "2.0", id: id, result: %{tools: @tools}}
  end

  def handle_message(%{"method" => "tools/call", "id" => id, "params" => params}, engine, cw) do
    tool_name = Map.get(params, "name", "")
    arguments = Map.get(params, "arguments", %{})

    case dispatch_tool(tool_name, arguments, engine) do
      {:ok, text} ->
        if cw && mutating_tool?(tool_name), do: ContextWriter.notify_mutation(cw)
        %{jsonrpc: "2.0", id: id, result: %{content: [%{type: "text", text: text}]}}

      {:error, text} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{content: [%{type: "text", text: text}], isError: true}
        }
    end
  end

  def handle_message(%{"id" => id}, _engine, _cw) do
    jsonrpc_error(id, -32601, "Method not found")
  end

  def handle_message(_msg, _engine, _cw), do: nil

  @spec dispatch_tool(String.t(), map(), atom()) :: {:ok, String.t()} | {:error, String.t()}
  def dispatch_tool(tool_name, arguments, engine) do
    case Map.get(@tool_to_command, tool_name) do
      nil ->
        {:error, "unknown tool: #{tool_name}"}

      command ->
        args = Protocol.decode_args(arguments)
        response = Dispatcher.dispatch(command, engine, args)

        if response.ok do
          {:ok, format_data(response.data)}
        else
          {:error, to_string(response.error)}
        end
    end
  end

  defp format_data(data) when is_binary(data), do: data
  defp format_data(:ok), do: "OK"
  defp format_data(data) when is_map(data), do: Jason.encode!(data)
  defp format_data(data), do: inspect(data)

  defp mutating_tool?(tool_name) do
    Map.get(@tool_to_command, tool_name) in @mutating_commands
  end

  defp jsonrpc_error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
