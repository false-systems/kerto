defmodule Kerto.Interface.Command.Init do
  @moduledoc "Initializes .kerto/ directory, .mcp.json, and .gitignore entries."

  alias Kerto.Interface.Response

  @kerto_dir ".kerto"
  @mcp_json ".mcp.json"
  @gitignore ".gitignore"
  @gitignore_entries [
    ".kerto/graph.etf",
    ".kerto/kerto.sock",
    ".kerto/kerto.pid",
    ".kerto/kerto.log"
  ]

  @spec execute(atom(), map()) :: Response.t()
  def execute(_engine, _args) do
    File.mkdir_p!(@kerto_dir)
    write_mcp_json()
    update_gitignore()
    Response.success("Initialized #{@kerto_dir}/ and #{@mcp_json}")
  end

  defp write_mcp_json do
    kerto_server = %{"command" => "kerto", "args" => ["mcp"]}

    existing =
      case File.read(@mcp_json) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} -> map
            {:error, _} -> %{}
          end

        {:error, _} ->
          %{}
      end

    servers =
      existing
      |> Map.get("mcpServers", %{})
      |> Map.put("kerto", kerto_server)

    merged = Map.put(existing, "mcpServers", servers)
    File.write!(@mcp_json, Jason.encode!(merged, pretty: true) <> "\n")
  end

  defp update_gitignore do
    existing =
      case File.read(@gitignore) do
        {:ok, content} -> content
        {:error, _} -> ""
      end

    lines = String.split(existing, "\n")

    new_entries =
      @gitignore_entries
      |> Enum.reject(&(&1 in lines))

    if new_entries != [] do
      suffix = if String.ends_with?(existing, "\n") or existing == "", do: "", else: "\n"
      File.write!(@gitignore, existing <> suffix <> Enum.join(new_entries, "\n") <> "\n")
    end
  end
end
