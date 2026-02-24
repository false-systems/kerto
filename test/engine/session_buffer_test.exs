defmodule Kerto.Engine.SessionBufferTest do
  use ExUnit.Case, async: false

  alias Kerto.Engine.SessionBuffer

  setup do
    pid =
      start_supervised!(
        {SessionBuffer, name: :test_session_buffer, auto_flush_interval_ms: :disabled}
      )

    %{buffer: :test_session_buffer, pid: pid}
  end

  test "track_edit adds file to session", %{buffer: buffer} do
    assert :ok = SessionBuffer.track_edit(buffer, "session-1", "auth.ex")
    assert ["session-1"] = SessionBuffer.list_sessions(buffer)
  end

  test "track_edit accumulates files in session", %{buffer: buffer} do
    SessionBuffer.track_edit(buffer, "s1", "auth.ex")
    SessionBuffer.track_edit(buffer, "s1", "cache.ex")
    SessionBuffer.track_edit(buffer, "s1", "auth.ex")

    {:ok, result} = SessionBuffer.flush(buffer, "s1")
    assert length(result.files) == 2
    assert "auth.ex" in result.files
    assert "cache.ex" in result.files
  end

  test "flush returns session data and removes it", %{buffer: buffer} do
    SessionBuffer.track_edit(buffer, "s1", "auth.ex")

    {:ok, result} = SessionBuffer.flush(buffer, "s1")
    assert result.agent == "s1"
    assert "auth.ex" in result.files

    assert {:error, :not_found} = SessionBuffer.flush(buffer, "s1")
  end

  test "flush returns error for unknown session", %{buffer: buffer} do
    assert {:error, :not_found} = SessionBuffer.flush(buffer, "nonexistent")
  end

  test "list_sessions returns all active session IDs", %{buffer: buffer} do
    SessionBuffer.track_edit(buffer, "s1", "a.ex")
    SessionBuffer.track_edit(buffer, "s2", "b.ex")

    sessions = SessionBuffer.list_sessions(buffer)
    assert length(sessions) == 2
    assert "s1" in sessions
    assert "s2" in sessions
  end

  test "concurrent sessions are independent", %{buffer: buffer} do
    SessionBuffer.track_edit(buffer, "s1", "auth.ex")
    SessionBuffer.track_edit(buffer, "s2", "cache.ex")
    SessionBuffer.track_edit(buffer, "s1", "token.ex")

    {:ok, s1} = SessionBuffer.flush(buffer, "s1")
    {:ok, s2} = SessionBuffer.flush(buffer, "s2")

    assert length(s1.files) == 2
    assert length(s2.files) == 1
  end

  test "auto-flush cleans up stale sessions" do
    {:ok, pid} =
      SessionBuffer.start_link(
        name: :test_auto_flush,
        auto_flush_interval_ms: 50,
        inactivity_timeout_ms: 0
      )

    SessionBuffer.track_edit(:test_auto_flush, "s1", "auth.ex")
    Process.sleep(100)

    assert SessionBuffer.list_sessions(:test_auto_flush) == []
    GenServer.stop(pid)
  end
end
