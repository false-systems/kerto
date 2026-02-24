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

  describe "AGENT.md" do
    test "writes .kerto/AGENT.md" do
      Init.execute(:unused, %{})
      assert File.exists?(".kerto/AGENT.md")
    end

    test "AGENT.md contains learning conventions" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".kerto/AGENT.md")
      assert content =~ "kerto_learn"
      assert content =~ "kerto_decide"
      assert content =~ "kerto_observe"
    end

    test "does not overwrite existing AGENT.md" do
      File.mkdir_p!(".kerto")
      File.write!(".kerto/AGENT.md", "custom content")
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".kerto/AGENT.md")
      assert content == "custom content"
    end

    test "adds AGENT.md to gitignore" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".gitignore")
      assert content =~ ".kerto/AGENT.md"
    end
  end

  describe "claude hooks" do
    test "writes .claude/hooks/post_tool_use.sh" do
      Init.execute(:unused, %{})
      assert File.exists?(".claude/hooks/post_tool_use.sh")
    end

    test "post_tool_use hook is executable" do
      Init.execute(:unused, %{})
      %{mode: mode} = File.stat!(".claude/hooks/post_tool_use.sh")
      assert Bitwise.band(mode, 0o111) != 0
    end

    test "post_tool_use hook filters to Write/Edit/MultiEdit and calls kerto ingest" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".claude/hooks/post_tool_use.sh")
      assert content =~ "Write|Edit|MultiEdit"
      assert content =~ "kerto ingest"
      assert content =~ "agent.file_edit"
    end

    test "writes .claude/hooks/stop.sh" do
      Init.execute(:unused, %{})
      assert File.exists?(".claude/hooks/stop.sh")
    end

    test "stop hook calls kerto observe with git context" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".claude/hooks/stop.sh")
      assert content =~ "kerto observe"
      assert content =~ "git rev-parse --abbrev-ref HEAD"
      assert content =~ "git log --oneline -5"
      assert content =~ "git diff --stat HEAD"
      assert content =~ "git status --porcelain"
      assert content =~ "BRANCH"
      assert content =~ "SUMMARY"
    end

    test "writes .claude/settings.json with hooks" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".claude/settings.json")
      decoded = Jason.decode!(content)
      assert is_list(decoded["hooks"]["PostToolUse"])
      assert is_list(decoded["hooks"]["Stop"])
    end

    test "merges into existing .claude/settings.json" do
      File.mkdir_p!(".claude")
      File.write!(".claude/settings.json", Jason.encode!(%{"existing" => true}))
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".claude/settings.json")
      decoded = Jason.decode!(content)
      assert decoded["existing"] == true
      assert decoded["hooks"]["PostToolUse"] != nil
    end

    test "does not duplicate hooks on re-init" do
      Init.execute(:unused, %{})
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".claude/settings.json")
      decoded = Jason.decode!(content)
      assert length(decoded["hooks"]["PostToolUse"]) == 1
      assert length(decoded["hooks"]["Stop"]) == 1
    end
  end

  describe "post-commit hook" do
    setup do
      File.mkdir_p!(".git/hooks")
      :ok
    end

    test "writes .git/hooks/post-commit when .git exists" do
      Init.execute(:unused, %{})
      assert File.exists?(".git/hooks/post-commit")
    end

    test "post-commit hook is executable" do
      Init.execute(:unused, %{})
      %{mode: mode} = File.stat!(".git/hooks/post-commit")
      assert Bitwise.band(mode, 0o111) != 0
    end

    test "post-commit hook calls kerto ingest" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".git/hooks/post-commit")
      assert content =~ "kerto ingest"
      assert content =~ "vcs.commit"
    end

    test "post-commit hook uses || true to never block commits" do
      Init.execute(:unused, %{})
      {:ok, content} = File.read(".git/hooks/post-commit")
      assert content =~ "|| true"
    end

    test "skips post-commit hook when .git does not exist" do
      File.rm_rf!(".git")
      Init.execute(:unused, %{})
      refute File.exists?(".git/hooks/post-commit")
    end
  end
end
