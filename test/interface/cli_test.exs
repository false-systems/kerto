defmodule Kerto.Interface.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Kerto.Interface.CLI

  test "run/1 dispatches status command" do
    output = capture_io(fn -> CLI.run(["status"]) end)
    assert output =~ "Nodes:"
  end

  test "run/1 dispatches status --json" do
    output = capture_io(fn -> CLI.run(["status", "--json"]) end)
    decoded = Jason.decode!(output)
    assert decoded["ok"] == true
    assert is_integer(decoded["data"]["nodes"])
  end

  test "run/1 dispatches context for missing entity" do
    output = capture_io(fn -> CLI.run(["context", "nonexistent.go"]) end)
    assert output =~ "Error"
  end

  test "run/1 reports unknown command" do
    output = capture_io(fn -> CLI.run(["explode"]) end)
    assert output =~ "Error"
    assert output =~ "unknown command"
  end

  test "run/1 reports missing command" do
    output = capture_io(fn -> CLI.run([]) end)
    assert output =~ "Error"
    assert output =~ "no command"
  end

  test "run/1 returns :ok for success" do
    result = capture_io(fn -> send(self(), CLI.run(["status"])) end)
    assert_received :ok
    assert result =~ "Nodes:"
  end

  test "run/1 returns :error for failure" do
    capture_io(fn -> send(self(), CLI.run(["context", "nope.go"])) end)
    assert_received :error
  end

  test "run/1 ingest and context round-trip" do
    capture_io(fn ->
      CLI.run([
        "learn",
        "auth.go handles authentication",
        "--subject",
        "auth.go",
        "--subject-kind",
        "file"
      ])
    end)

    output =
      capture_io(fn ->
        CLI.run(["context", "auth.go", "--kind", "file"])
      end)

    assert output =~ "auth.go"
  end
end
