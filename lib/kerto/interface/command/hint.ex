defmodule Kerto.Interface.Command.Hint do
  @moduledoc "Returns compact hints for given files."

  alias Kerto.Interface.Response
  alias Kerto.Rendering.{HintRenderer, Query}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    files = normalize_files(Map.get(args, :files, []))

    graph = Kerto.Engine.get_graph(engine)

    contexts =
      files
      |> Enum.map(fn file ->
        case Query.query_context(graph, :file, file, "", depth: 1) do
          {:ok, ctx} -> ctx
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    hint = HintRenderer.render(contexts)

    if hint == "" do
      Response.success("")
    else
      Response.success(hint)
    end
  end

  defp normalize_files(files) when is_list(files), do: files
  defp normalize_files(files) when is_binary(files), do: String.split(files, ",", trim: true)
  defp normalize_files(_), do: []
end
