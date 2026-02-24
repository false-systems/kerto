defmodule Kerto.Engine.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.SessionRegistry

  setup do
    pid =
      start_supervised!({SessionRegistry, name: :test_session_registry})

    %{registry: :test_session_registry, pid: pid}
  end

  test "register returns a session ID", %{registry: registry} do
    {:ok, session_id} = SessionRegistry.register(registry, "claude-1")
    assert is_binary(session_id)
    assert byte_size(session_id) > 0
  end

  test "register creates unique session IDs", %{registry: registry} do
    {:ok, id1} = SessionRegistry.register(registry, "claude-1")
    {:ok, id2} = SessionRegistry.register(registry, "claude-2")
    assert id1 != id2
  end

  test "active_sessions lists registered sessions", %{registry: registry} do
    {:ok, _} = SessionRegistry.register(registry, "claude-1")
    {:ok, _} = SessionRegistry.register(registry, "claude-2")

    sessions = SessionRegistry.active_sessions(registry)
    assert length(sessions) == 2
    agents = Enum.map(sessions, & &1.agent)
    assert "claude-1" in agents
    assert "claude-2" in agents
  end

  test "deregister removes session", %{registry: registry} do
    {:ok, session_id} = SessionRegistry.register(registry, "claude-1")
    :ok = SessionRegistry.deregister(registry, session_id)

    assert SessionRegistry.active_sessions(registry) == []
  end

  test "track_file adds files to session", %{registry: registry} do
    {:ok, session_id} = SessionRegistry.register(registry, "claude-1")
    :ok = SessionRegistry.track_file(registry, session_id, "auth.ex")
    :ok = SessionRegistry.track_file(registry, session_id, "cache.ex")

    {:ok, files} = SessionRegistry.session_files(registry, session_id)
    assert length(files) == 2
    assert "auth.ex" in files
    assert "cache.ex" in files
  end

  test "track_file deduplicates", %{registry: registry} do
    {:ok, session_id} = SessionRegistry.register(registry, "claude-1")
    SessionRegistry.track_file(registry, session_id, "auth.ex")
    SessionRegistry.track_file(registry, session_id, "auth.ex")

    {:ok, files} = SessionRegistry.session_files(registry, session_id)
    assert length(files) == 1
  end

  test "active_files returns all files across sessions", %{registry: registry} do
    {:ok, s1} = SessionRegistry.register(registry, "claude-1")
    {:ok, s2} = SessionRegistry.register(registry, "claude-2")

    SessionRegistry.track_file(registry, s1, "auth.ex")
    SessionRegistry.track_file(registry, s2, "cache.ex")
    SessionRegistry.track_file(registry, s2, "auth.ex")

    files = SessionRegistry.active_files(registry)
    assert length(files) == 2
    assert "auth.ex" in files
    assert "cache.ex" in files
  end

  test "session_files returns error for unknown session", %{registry: registry} do
    assert {:error, :not_found} = SessionRegistry.session_files(registry, "nonexistent")
  end

  test "track_file is no-op for unknown session", %{registry: registry} do
    assert :ok = SessionRegistry.track_file(registry, "nonexistent", "auth.ex")
  end

  test "active_sessions shows file counts", %{registry: registry} do
    {:ok, s1} = SessionRegistry.register(registry, "claude-1")
    SessionRegistry.track_file(registry, s1, "auth.ex")
    SessionRegistry.track_file(registry, s1, "cache.ex")

    [session] = SessionRegistry.active_sessions(registry)
    assert session.file_count == 2
  end
end
