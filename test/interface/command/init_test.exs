defmodule Kerto.Interface.Command.InitTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Init

  @test_dir System.tmp_dir!()
            |> Path.join("kerto_init_test_#{System.unique_integer([:positive])}")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    prev_dir = File.cwd!()
    File.cd!(@test_dir)
    on_exit(fn -> File.cd!(prev_dir) end)
    :ok
  end

  test "creates .kerto directory" do
    resp = Init.execute(:unused, %{})
    assert resp.ok
    assert File.dir?(".kerto")
  end

  test "creates .mcp.json with kerto server" do
    Init.execute(:unused, %{})
    {:ok, content} = File.read(".mcp.json")
    decoded = Jason.decode!(content)
    assert decoded["mcpServers"]["kerto"]["command"] == "kerto"
    assert decoded["mcpServers"]["kerto"]["args"] == ["mcp"]
  end

  test "merges into existing .mcp.json without overwriting" do
    existing = %{"mcpServers" => %{"other" => %{"command" => "other"}}}
    File.write!(".mcp.json", Jason.encode!(existing))

    Init.execute(:unused, %{})
    {:ok, content} = File.read(".mcp.json")
    decoded = Jason.decode!(content)
    assert decoded["mcpServers"]["other"]["command"] == "other"
    assert decoded["mcpServers"]["kerto"]["command"] == "kerto"
  end

  test "adds entries to .gitignore" do
    Init.execute(:unused, %{})
    {:ok, content} = File.read(".gitignore")
    assert content =~ ".kerto/graph.etf"
    assert content =~ ".kerto/kerto.sock"
    assert content =~ ".kerto/kerto.pid"
    assert content =~ ".kerto/kerto.log"
  end

  test "does not duplicate .gitignore entries on re-init" do
    Init.execute(:unused, %{})
    Init.execute(:unused, %{})
    {:ok, content} = File.read(".gitignore")
    count = content |> String.split(".kerto/graph.etf") |> length()
    assert count == 2
  end

  test "appends to existing .gitignore" do
    File.write!(".gitignore", "node_modules/\n")
    Init.execute(:unused, %{})
    {:ok, content} = File.read(".gitignore")
    assert content =~ "node_modules/"
    assert content =~ ".kerto/graph.etf"
  end
end
