defmodule Kerto.Engine.SessionBuffer do
  @moduledoc """
  Accumulates file edits per session, flushes as batch at session end.

  Tracks which files were edited in each agent session. On flush,
  returns the accumulated files for co-edit relationship creation.
  Auto-flushes sessions inactive for more than 5 minutes.
  """

  use GenServer

  @auto_flush_interval_ms 60_000
  @inactivity_timeout_ms 300_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec track_edit(GenServer.server(), String.t(), String.t()) :: :ok
  def track_edit(server \\ __MODULE__, session_id, file)
      when is_binary(session_id) and is_binary(file) do
    GenServer.call(server, {:track_edit, session_id, file})
  end

  @spec flush(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def flush(server \\ __MODULE__, session_id) when is_binary(session_id) do
    GenServer.call(server, {:flush, session_id})
  end

  @spec list_sessions(GenServer.server()) :: [String.t()]
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions)
  end

  # --- Server ---

  @impl true
  def init(opts) do
    auto_flush_ms = Keyword.get(opts, :auto_flush_interval_ms, @auto_flush_interval_ms)
    inactivity_ms = Keyword.get(opts, :inactivity_timeout_ms, @inactivity_timeout_ms)

    if auto_flush_ms != :disabled do
      Process.send_after(self(), :auto_flush, auto_flush_ms)
    end

    {:ok,
     %{
       sessions: %{},
       auto_flush_interval_ms: auto_flush_ms,
       inactivity_timeout_ms: inactivity_ms
     }}
  end

  @impl true
  def handle_call({:track_edit, session_id, file}, _from, state) do
    session =
      Map.get(state.sessions, session_id, %{
        agent: session_id,
        files: MapSet.new(),
        last_active: now_ms()
      })

    session = %{session | files: MapSet.put(session.files, file), last_active: now_ms()}
    {:reply, :ok, %{state | sessions: Map.put(state.sessions, session_id, session)}}
  end

  def handle_call({:flush, session_id}, _from, state) do
    case Map.pop(state.sessions, session_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {session, sessions} ->
        result = %{agent: session.agent, files: MapSet.to_list(session.files)}
        {:reply, {:ok, result}, %{state | sessions: sessions}}
    end
  end

  def handle_call(:list_sessions, _from, state) do
    {:reply, Map.keys(state.sessions), state}
  end

  @impl true
  def handle_info(:auto_flush, state) do
    cutoff = now_ms() - state.inactivity_timeout_ms

    {stale, active} =
      Enum.split_with(state.sessions, fn {_id, session} ->
        session.last_active < cutoff
      end)

    stale_results =
      Enum.map(stale, fn {id, session} ->
        {id, %{agent: session.agent, files: MapSet.to_list(session.files)}}
      end)

    if state.auto_flush_interval_ms != :disabled do
      Process.send_after(self(), :auto_flush, state.auto_flush_interval_ms)
    end

    {:noreply, %{state | sessions: Map.new(active)}, {:continue, {:flush_stale, stale_results}}}
  end

  @impl true
  def handle_continue({:flush_stale, _stale_results}, state) do
    # Stale sessions are removed from state. In a full implementation,
    # these would be ingested as session_edits occurrences.
    # For now, they're simply cleaned up.
    {:noreply, state}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
