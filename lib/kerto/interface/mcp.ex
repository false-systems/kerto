defmodule Kerto.Interface.MCP do
  @moduledoc "MCP server over stdio (JSON-RPC 2.0, newline-delimited)."

  alias Kerto.Interface.{ContextWriter, Dispatcher, Protocol}

  @mutating_commands ~w(learn decide ingest observe decay weaken delete forget pin unpin scan)

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
      name: "kerto_observe",
      description: "Record a session summary of what was discovered or changed",
      inputSchema: %{
        type: "object",
        properties: %{
          summary: %{type: "string", description: "1-3 sentence summary of the session"},
          files: %{
            type: "array",
            items: %{type: "string"},
            description: "Central files worked on during the session"
          },
          session_id: %{type: "string", description: "Optional session identifier"}
        },
        required: ["summary"]
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
    },
    %{
      name: "kerto_hint",
      description: "Get compact hints for files about to be edited",
      inputSchema: %{
        type: "object",
        properties: %{
          files: %{
            type: "array",
            items: %{type: "string"},
            description: "File paths to get hints for"
          }
        },
        required: ["files"]
      }
    },
    %{
      name: "kerto_forget",
      description: "Remove a node or relationship from the knowledge graph",
      inputSchema: %{
        type: "object",
        properties: %{
          node: %{type: "string", description: "Node name to forget"},
          kind: %{type: "string", description: "Node kind (default: file)"},
          source: %{type: "string", description: "Source name (for relationship forget)"},
          relation: %{type: "string", description: "Relationship type"},
          target: %{type: "string", description: "Target name (for relationship forget)"},
          source_kind: %{type: "string", description: "Source kind (default: file)"},
          target_kind: %{type: "string", description: "Target kind (default: file)"}
        }
      }
    },
    %{
      name: "kerto_pin",
      description: "Pin a node or relationship so it never decays or gets pruned",
      inputSchema: %{
        type: "object",
        properties: %{
          node: %{type: "string", description: "Node name to pin"},
          kind: %{type: "string", description: "Node kind (default: file)"},
          source: %{type: "string", description: "Source name (for relationship pin)"},
          relation: %{type: "string", description: "Relationship type"},
          target: %{type: "string", description: "Target name (for relationship pin)"},
          source_kind: %{type: "string", description: "Source kind (default: file)"},
          target_kind: %{type: "string", description: "Target kind (default: file)"}
        }
      }
    },
    %{
      name: "kerto_unpin",
      description: "Unpin a node or relationship, allowing normal decay",
      inputSchema: %{
        type: "object",
        properties: %{
          node: %{type: "string", description: "Node name to unpin"},
          kind: %{type: "string", description: "Node kind (default: file)"},
          source: %{type: "string", description: "Source name (for relationship unpin)"},
          relation: %{type: "string", description: "Relationship type"},
          target: %{type: "string", description: "Target name (for relationship unpin)"},
          source_kind: %{type: "string", description: "Source kind (default: file)"},
          target_kind: %{type: "string", description: "Target kind (default: file)"}
        }
      }
    },
    %{
      name: "kerto_team",
      description: "Manage team PKI (CA, certificates, membership)",
      inputSchema: %{
        type: "object",
        properties: %{
          action: %{type: "string", description: "init, join, sign, or list"},
          name: %{type: "string", description: "Team or node name"},
          csr: %{type: "string", description: "Path to CSR file (for sign)"}
        },
        required: ["action"]
      }
    },
    %{
      name: "kerto_mesh",
      description: "Manage mesh network (peers, connections)",
      inputSchema: %{
        type: "object",
        properties: %{
          action: %{type: "string", description: "status, connect, add-peer, or remove-peer"},
          peer: %{type: "string", description: "Peer node name (node@host)"}
        },
        required: ["action"]
      }
    },
    %{
      name: "kerto_scan",
      description: "Manually trigger a plugin scan cycle for passive learning",
      inputSchema: %{type: "object", properties: %{}}
    },
    %{
      name: "kerto_list",
      description: "List nodes or relationships with optional filters",
      inputSchema: %{
        type: "object",
        properties: %{
          type: %{
            type: "string",
            description: "What to list: nodes or relationships (default: nodes)"
          },
          kind: %{type: "string", description: "Filter by node kind"},
          pinned: %{type: "boolean", description: "Show only pinned entities"},
          below: %{type: "number", description: "Show entities below this relevance/weight"},
          relation: %{type: "string", description: "Filter by relation type (relationships only)"}
        }
      }
    }
  ]

  @tool_to_command %{
    "kerto_context" => "context",
    "kerto_learn" => "learn",
    "kerto_decide" => "decide",
    "kerto_status" => "status",
    "kerto_graph" => "graph",
    "kerto_observe" => "observe",
    "kerto_weaken" => "weaken",
    "kerto_hint" => "hint",
    "kerto_forget" => "forget",
    "kerto_pin" => "pin",
    "kerto_unpin" => "unpin",
    "kerto_list" => "list",
    "kerto_scan" => "scan",
    "kerto_team" => "team",
    "kerto_mesh" => "mesh"
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
