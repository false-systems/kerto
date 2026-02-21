defmodule Kerto.Interface.ContextWriter do
  @moduledoc "Auto-renders .kerto/CONTEXT.md on graph mutations with debouncing."

  use GenServer

  alias Kerto.Rendering.{Query, Renderer}

  @default_debounce_ms 2_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec notify_mutation(GenServer.server()) :: :ok
  def notify_mutation(server \\ __MODULE__) do
    GenServer.cast(server, :mutation)
  end

  @spec render_full_context(Kerto.Graph.Graph.t()) :: String.t()
  def render_full_context(graph) do
    nodes =
      Kerto.Graph.Graph.list_nodes(graph)
      |> Enum.take(20)

    sections =
      nodes
      |> Enum.map(fn node ->
        case Query.query_context(graph, node.kind, node.name, "") do
          {:ok, ctx} -> Renderer.render(ctx)
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    header = "# Kerto Knowledge Context\n\n_Auto-generated. Do not edit._\n"

    case sections do
      [] -> header <> "\nNo knowledge recorded yet.\n"
      _ -> header <> "\n" <> Enum.join(sections, "\n\n---\n\n") <> "\n"
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    engine = Keyword.fetch!(opts, :engine)
    path = Keyword.get(opts, :path, ".kerto/CONTEXT.md")
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)

    {:ok, %{engine: engine, path: path, debounce_ms: debounce_ms, timer: nil}}
  end

  @impl true
  def handle_cast(:mutation, state) do
    state = reset_timer(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:render, state) do
    graph = Kerto.Engine.get_graph(state.engine)
    content = render_full_context(graph)

    state.path |> Path.dirname() |> File.mkdir_p!()
    File.write!(state.path, content)

    {:noreply, %{state | timer: nil}}
  end

  @impl true
  def terminate(_reason, %{timer: timer} = state) when not is_nil(timer) do
    Process.cancel_timer(timer)
    flush_render(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp flush_render(state) do
    graph = Kerto.Engine.get_graph(state.engine)
    content = render_full_context(graph)
    state.path |> Path.dirname() |> File.mkdir_p!()
    File.write!(state.path, content)
  rescue
    _ -> :ok
  end

  defp reset_timer(%{timer: old_timer} = state) do
    if old_timer, do: Process.cancel_timer(old_timer)
    timer = Process.send_after(self(), :render, state.debounce_ms)
    %{state | timer: timer}
  end
end
