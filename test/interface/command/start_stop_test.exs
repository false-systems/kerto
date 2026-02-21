defmodule Kerto.Interface.Command.StartStopTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.{Start, Stop}
  alias Kerto.Interface.{Daemon, DaemonClient}

  @test_dir System.tmp_dir!()
            |> Path.join("kerto_startstop_test_#{System.unique_integer([:positive])}")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(Path.join(@test_dir, ".kerto"))
    prev_dir = File.cwd!()
    File.cd!(@test_dir)
    on_exit(fn -> File.cd!(prev_dir) end)
    :ok
  end

  test "stop returns error when daemon not running" do
    resp = Stop.execute(:unused, %{})
    assert resp.ok == false
    assert resp.error =~ "not running"
  end

  test "stop sends shutdown to running daemon" do
    socket_path = Path.join(@test_dir, ".kerto/kerto.sock")
    engine = :"test_ss_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       name: :"test_ss_daemon_#{System.unique_integer([:positive])}"}
    )

    Process.sleep(50)

    assert DaemonClient.daemon_running?(socket_path)

    resp = Stop.execute(:unused, %{})
    assert resp.ok
    assert resp.data =~ "stopped"
  end

  test "start detects already running daemon" do
    socket_path = Path.join(@test_dir, ".kerto/kerto.sock")
    engine = :"test_ss2_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       name: :"test_ss2_daemon_#{System.unique_integer([:positive])}"}
    )

    Process.sleep(50)

    resp = Start.execute(:unused, %{})
    assert resp.ok
    assert resp.data =~ "already running"
  end

  test "start returns error when escript not found" do
    resp = Start.execute(:unused, %{})
    assert resp.ok == false
    assert resp.error =~ "cannot find"
  end

  test "start cleans up stale PID file" do
    File.write!(".kerto/kerto.pid", "999999999")
    File.write!(".kerto/kerto.sock", "stale")

    _resp = Start.execute(:unused, %{})

    refute File.exists?(".kerto/kerto.pid")
    refute File.exists?(".kerto/kerto.sock")
  end

  test "os_pid_alive?/1 detects dead PID" do
    refute Start.os_pid_alive?("999999999")
  end

  test "os_pid_alive?/1 detects live PID" do
    assert Start.os_pid_alive?(to_string(System.pid() |> String.trim()))
  end
end
