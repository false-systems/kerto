defmodule Kerto.Interface.DaemonSessionTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.{Daemon, DaemonClient}

  @socket_path System.tmp_dir!()
               |> Path.join(
                 "kerto_daemon_session_test_#{System.unique_integer([:positive])}.sock"
               )

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_daemon_session_engine, decay_interval_ms: :timer.hours(1)}
    )

    start_supervised!(
      {Daemon,
       socket_path: @socket_path,
       engine: :test_daemon_session_engine,
       context_writer: nil,
       name: :test_daemon_session}
    )

    on_exit(fn -> File.rm(@socket_path) end)
    %{socket: @socket_path, engine: :test_daemon_session_engine}
  end

  test "register command returns a session ID", %{socket: socket} do
    {:ok, %{"ok" => true, "data" => session_id}} =
      DaemonClient.send_command(socket, "register", %{"agent" => "claude-1"})

    assert is_binary(session_id)
    assert byte_size(session_id) > 0
  end

  test "deregister command succeeds", %{socket: socket} do
    {:ok, %{"ok" => true, "data" => session_id}} =
      DaemonClient.send_command(socket, "register", %{"agent" => "claude-1"})

    {:ok, %{"ok" => true}} =
      DaemonClient.send_command(socket, "deregister", %{"session" => session_id})
  end

  test "concurrent connections work", %{socket: socket} do
    tasks =
      for i <- 1..3 do
        Task.async(fn ->
          DaemonClient.send_command(socket, "register", %{"agent" => "agent-#{i}"})
        end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:ok, %{"ok" => true}} -> true
             _ -> false
           end)
  end

  test "commands work without session_id (backward compat)", %{socket: socket} do
    {:ok, %{"ok" => true}} = DaemonClient.send_command(socket, "status", %{})
  end
end
