defmodule Kerto.Interface.CLISocketTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Kerto.Interface.{CLI, Daemon}

  @test_dir System.tmp_dir!()
            |> Path.join("kerto_cli_socket_test_#{System.unique_integer([:positive])}")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(Path.join(@test_dir, ".kerto"))
    prev_dir = File.cwd!()
    File.cd!(@test_dir)

    socket_path = Path.join(@test_dir, ".kerto/kerto.sock")
    engine = :"test_cli_sock_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    start_supervised!(
      {Daemon,
       socket_path: socket_path,
       engine: engine,
       name: :"test_cli_sock_daemon_#{System.unique_integer([:positive])}"}
    )

    Process.sleep(50)
    on_exit(fn -> File.cd!(prev_dir) end)
    %{engine: engine}
  end

  test "routes status through socket when daemon running" do
    output = capture_io(fn -> CLI.run(["status"]) end)
    assert output =~ "nodes"
  end

  test "routes learn through socket and queries back" do
    capture_io(fn ->
      CLI.run([
        "learn",
        "auth handles auth",
        "--subject",
        "auth.go",
        "--target",
        "auth",
        "--target-kind",
        "concept",
        "--relation",
        "learned"
      ])
    end)

    output = capture_io(fn -> CLI.run(["context", "auth.go"]) end)
    assert output =~ "auth.go"
  end

  test "init command runs directly even with daemon" do
    output = capture_io(fn -> CLI.run(["init"]) end)
    assert output =~ "Initialized"
  end

  test "help shows new commands" do
    output = capture_io(fn -> CLI.run(["--help"]) end)
    assert output =~ "init"
    assert output =~ "start"
    assert output =~ "stop"
  end

  test "init --help shows init help" do
    output = capture_io(fn -> CLI.run(["init", "--help"]) end)
    assert output =~ ".kerto"
  end
end
