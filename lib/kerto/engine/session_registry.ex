defmodule Kerto.Engine.SessionRegistry do
  @moduledoc """
  Tracks active agent sessions for multi-agent coordination.

  Each session represents one AI agent instance connected to the graph.
  Tracks which files each session is actively working on, enabling
  cross-session hints and session-aware context rendering.
  """

  use GenServer

  alias Kerto.Graph.ULID

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec register(GenServer.server(), String.t()) :: {:ok, String.t()}
  def register(server \\ __MODULE__, agent_name) when is_binary(agent_name) do
    GenServer.call(server, {:register, agent_name})
  end

  @spec deregister(GenServer.server(), String.t()) :: :ok
  def deregister(server \\ __MODULE__, session_id) when is_binary(session_id) do
    GenServer.call(server, {:deregister, session_id})
  end

  @spec track_file(GenServer.server(), String.t(), String.t()) :: :ok
  def track_file(server \\ __MODULE__, session_id, file)
      when is_binary(session_id) and is_binary(file) do
    GenServer.call(server, {:track_file, session_id, file})
  end

  @spec active_sessions(GenServer.server()) :: [map()]
  def active_sessions(server \\ __MODULE__) do
    GenServer.call(server, :active_sessions)
  end

  @spec active_files(GenServer.server()) :: [String.t()]
  def active_files(server \\ __MODULE__) do
    GenServer.call(server, :active_files)
  end

  @spec session_files(GenServer.server(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def session_files(server \\ __MODULE__, session_id) when is_binary(session_id) do
    GenServer.call(server, {:session_files, session_id})
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:register, agent_name}, _from, state) do
    session_id = ULID.generate()

    session = %{
      agent: agent_name,
      started: session_id,
      files: MapSet.new()
    }

    {:reply, {:ok, session_id}, %{state | sessions: Map.put(state.sessions, session_id, session)}}
  end

  def handle_call({:deregister, session_id}, _from, state) do
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  def handle_call({:track_file, session_id, file}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :ok, state}

      session ->
        session = %{session | files: MapSet.put(session.files, file)}
        {:reply, :ok, %{state | sessions: Map.put(state.sessions, session_id, session)}}
    end
  end

  def handle_call(:active_sessions, _from, state) do
    sessions =
      state.sessions
      |> Enum.map(fn {id, session} ->
        %{
          session_id: id,
          agent: session.agent,
          file_count: MapSet.size(session.files)
        }
      end)

    {:reply, sessions, state}
  end

  def handle_call(:active_files, _from, state) do
    files =
      state.sessions
      |> Map.values()
      |> Enum.flat_map(&MapSet.to_list(&1.files))
      |> Enum.uniq()

    {:reply, files, state}
  end

  def handle_call({:session_files, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> {:reply, {:ok, MapSet.to_list(session.files)}, state}
    end
  end
end
