defmodule Kerto.Interface.DaemonClientTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.{Daemon, DaemonClient}

  @test_dir System.tmp_dir!() |> Path.join("kerto_dc_test")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    socket_path = Path.join(@test_dir, "dc_#{System.unique_integer([:positive])}.sock")
    engine = :"test_dc_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       name: :"test_dc_daemon_#{System.unique_integer([:positive])}"}
    )

    Process.sleep(50)
    %{socket_path: socket_path, engine: engine}
  end

  test "send_command/3 sends and receives", %{socket_path: path} do
    assert {:ok, %{"ok" => true}} = DaemonClient.send_command(path, "status")
  end

  test "send_command/3 with args", %{socket_path: path} do
    args = %{
      evidence: "test",
      subject: "a.go",
      subject_kind: "file",
      target: "b",
      target_kind: "concept",
      relation: "learned"
    }

    assert {:ok, %{"ok" => true}} = DaemonClient.send_command(path, "learn", args)
  end

  test "daemon_running?/1 returns true when daemon is up", %{socket_path: path} do
    assert DaemonClient.daemon_running?(path)
  end

  test "daemon_running?/1 returns false when no daemon" do
    refute DaemonClient.daemon_running?("/tmp/nonexistent_kerto.sock")
  end

  test "send_command/3 returns error when daemon not running" do
    assert {:error, _} = DaemonClient.send_command("/tmp/nonexistent_kerto.sock", "status")
  end
end
