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
    System.cmd("git", ["init"])
    System.cmd("git", ["config", "user.email", "test@test.com"])
    System.cmd("git", ["config", "user.name", "Test"])
    File.write!("README.md", "test")
    System.cmd("git", ["add", "."])
    System.cmd("git", ["commit", "-m", "initial"])
    start_supervised!({Kerto.Engine, name: :test_init_engine, decay_interval_ms: :timer.hours(1)})

    on_exit(fn ->
      File.cd!(prev_dir)
      File.rm_rf!(@test_dir)
    end)

    %{engine: :test_init_engine}
  end

  test "creates .kerto directory", %{engine: engine} do
    resp = Init.execute(engine, %{})
    assert resp.ok
    assert File.dir?(".kerto")
  end

  test "creates .mcp.json with kerto server", %{engine: engine} do
    Init.execute(engine, %{})
    {:ok, content} = File.read(".mcp.json")
    decoded = Jason.decode!(content)
    assert decoded["mcpServers"]["kerto"]["command"] == "kerto"
    assert decoded["mcpServers"]["kerto"]["args"] == ["mcp"]
  end

  test "merges into existing .mcp.json without overwriting", %{engine: engine} do
    existing = %{"mcpServers" => %{"other" => %{"command" => "other"}}}
    File.write!(".mcp.json", Jason.encode!(existing))

    Init.execute(engine, %{})
    {:ok, content} = File.read(".mcp.json")
    decoded = Jason.decode!(content)
    assert decoded["mcpServers"]["other"]["command"] == "other"
    assert decoded["mcpServers"]["kerto"]["command"] == "kerto"
  end

  test "adds entries to .gitignore", %{engine: engine} do
    Init.execute(engine, %{})
    {:ok, content} = File.read(".gitignore")
    assert content =~ ".kerto/graph.etf"
    assert content =~ ".kerto/kerto.sock"
    assert content =~ ".kerto/kerto.pid"
    assert content =~ ".kerto/kerto.log"
  end

  test "does not duplicate .gitignore entries on re-init", %{engine: engine} do
    Init.execute(engine, %{})
    Init.execute(engine, %{})
    {:ok, content} = File.read(".gitignore")
    count = content |> String.split(".kerto/graph.etf") |> length()
    assert count == 2
  end

  test "appends to existing .gitignore", %{engine: engine} do
    File.write!(".gitignore", "node_modules/\n")
    Init.execute(engine, %{})
    {:ok, content} = File.read(".gitignore")
    assert content =~ "node_modules/"
    assert content =~ ".kerto/graph.etf"
  end

  test "does not create .claude/hooks/", %{engine: engine} do
    Init.execute(engine, %{})
    refute File.dir?(".claude/hooks")
  end

  test "does not create .claude/settings.json", %{engine: engine} do
    Init.execute(engine, %{})
    refute File.exists?(".claude/settings.json")
  end

  test "does not create .git/hooks/post-commit", %{engine: engine} do
    Init.execute(engine, %{})
    refute File.exists?(".git/hooks/post-commit")
  end

  test "runs bootstrap to seed graph from git history", %{engine: engine} do
    Init.execute(engine, %{})
    assert Kerto.Engine.node_count(engine) > 0
  end

  describe "AGENT.md" do
    test "writes .kerto/AGENT.md", %{engine: engine} do
      Init.execute(engine, %{})
      assert File.exists?(".kerto/AGENT.md")
    end

    test "AGENT.md contains learning conventions", %{engine: engine} do
      Init.execute(engine, %{})
      {:ok, content} = File.read(".kerto/AGENT.md")
      assert content =~ "kerto_learn"
      assert content =~ "kerto_decide"
      assert content =~ "kerto_observe"
    end

    test "does not overwrite existing AGENT.md", %{engine: engine} do
      File.mkdir_p!(".kerto")
      File.write!(".kerto/AGENT.md", "custom content")
      Init.execute(engine, %{})
      {:ok, content} = File.read(".kerto/AGENT.md")
      assert content == "custom content"
    end

    test "adds AGENT.md to gitignore", %{engine: engine} do
      Init.execute(engine, %{})
      {:ok, content} = File.read(".gitignore")
      assert content =~ ".kerto/AGENT.md"
    end
  end
end
