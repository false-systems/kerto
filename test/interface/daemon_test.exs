defmodule Kerto.Interface.DaemonTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Daemon
  alias Kerto.Ingestion.{Occurrence, Source}

  @test_dir System.tmp_dir!() |> Path.join("kerto_daemon_test")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    socket_path = Path.join(@test_dir, "test_#{System.unique_integer([:positive])}.sock")
    engine = :"test_daemon_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       name: :"test_daemon_#{System.unique_integer([:positive])}"}
    )

    Process.sleep(50)
    %{socket_path: socket_path, engine: engine}
  end

  test "accepts status command over socket", %{socket_path: path} do
    {:ok, response} = send_command(path, "status")
    assert response["ok"] == true
    assert is_integer(response["data"]["nodes"])
  end

  test "accepts learn command and updates graph", %{socket_path: path, engine: engine} do
    args = %{
      evidence: "auth handles auth",
      subject: "auth.go",
      subject_kind: "file",
      target: "authentication",
      target_kind: "concept",
      relation: "learned"
    }

    {:ok, response} = send_command(path, "learn", args)
    assert response["ok"] == true
    assert Kerto.Engine.node_count(engine) >= 1
  end

  test "returns error for unknown command", %{socket_path: path} do
    {:ok, response} = send_command(path, "nonexistent")
    assert response["ok"] == false
    assert response["error"] =~ "unknown command"
  end

  test "returns error for invalid JSON", %{socket_path: path} do
    {:ok, socket} = connect(path)
    :gen_tcp.send(socket, "not json\n")
    {:ok, line} = :gen_tcp.recv(socket, 0, 5_000)
    :gen_tcp.close(socket)
    response = Jason.decode!(line)
    assert response["ok"] == false
    assert response["error"] =~ "invalid JSON"
  end

  test "handles context query round-trip", %{socket_path: path, engine: engine} do
    occ =
      Occurrence.new(
        "context.learning",
        %{
          subject_kind: :file,
          subject_name: "router.go",
          target_kind: :concept,
          target_name: "routing",
          relation: :learned,
          evidence: "router handles routing"
        },
        Source.new("test", "test", "01TEST01")
      )

    Kerto.Engine.ingest(engine, occ)

    {:ok, response} = send_command(path, "context", %{name: "router.go", kind: "file"})
    assert response["ok"] == true
    assert response["data"] =~ "router.go"
  end

  test "cleans up socket file on terminate", %{socket_path: path} do
    assert File.exists?(path)
    stop_supervised!(Daemon)
    Process.sleep(50)
    refute File.exists?(path)
  end

  test "shutdown command stops daemon cleanly" do
    socket_path = Path.join(@test_dir, "shutdown_test.sock")
    engine = :"test_shutdown_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)},
      id: :shutdown_engine
    )

    daemon_name = :"test_shutdown_daemon_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Daemon, socket_path: socket_path, engine: engine, name: daemon_name},
      id: :shutdown_daemon
    )

    Process.sleep(50)
    ref = Process.monitor(Process.whereis(daemon_name))

    {:ok, response} = send_command(socket_path, "shutdown")
    assert response["ok"] == true

    assert_receive {:DOWN, ^ref, :process, _, :normal}, 1_000
    refute File.exists?(socket_path)
  end

  test "removes stale socket on init" do
    stale_path = Path.join(@test_dir, "stale.sock")
    File.write!(stale_path, "stale")

    engine = :"test_stale_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)},
      id: :stale_engine
    )

    start_supervised!(
      {Daemon, socket_path: stale_path, engine: engine, name: :test_stale_daemon},
      id: :stale_daemon
    )

    Process.sleep(50)
    {:ok, response} = send_command(stale_path, "status")
    assert response["ok"] == true
  end

  test "notifies context writer on mutating command" do
    socket_path = Path.join(@test_dir, "cw_notify.sock")
    engine = :"test_cw_notify_engine_#{System.unique_integer([:positive])}"
    cw_path = Path.join(@test_dir, "CONTEXT.md")

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)},
      id: :cw_engine
    )

    start_supervised!(
      {Kerto.Interface.ContextWriter,
       engine: engine, path: cw_path, debounce_ms: 10, name: :test_cw_daemon},
      id: :cw_writer
    )

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       context_writer: :test_cw_daemon,
       name: :test_cw_daemon_d},
      id: :cw_daemon
    )

    Process.sleep(50)

    send_command(socket_path, "learn", %{
      evidence: "test context writer",
      subject: "cw.go",
      subject_kind: "file",
      target: "testing",
      target_kind: "concept",
      relation: "learned"
    })

    Process.sleep(100)
    assert File.exists?(cw_path)
    assert File.read!(cw_path) =~ "cw.go"
  end

  defp send_command(path, command, args \\ %{}) do
    with {:ok, socket} <- connect(path) do
      payload = Jason.encode!(%{command: command, args: args}) <> "\n"
      :gen_tcp.send(socket, payload)

      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, line} ->
          :gen_tcp.close(socket)
          {:ok, Jason.decode!(line)}

        {:error, reason} ->
          :gen_tcp.close(socket)
          {:error, reason}
      end
    end
  end

  defp connect(path) do
    :gen_tcp.connect({:local, path}, 0, [:binary, packet: :line, active: false], 5_000)
  end
end
