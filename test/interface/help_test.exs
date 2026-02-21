defmodule Kerto.Interface.HelpTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.Help
  alias Kerto.Interface.Dispatcher

  describe "render/1 global help" do
    test "lists all commands" do
      text = Help.render(nil)

      for cmd <- Dispatcher.commands() do
        assert text =~ cmd, "global help missing command: #{cmd}"
      end
    end

    test "includes usage line" do
      text = Help.render(nil)
      assert text =~ "Usage:"
      assert text =~ "kerto"
    end
  end

  describe "render/1 per-command help" do
    test "shows usage and description for known command" do
      text = Help.render("context")
      assert text =~ "context"
      assert text =~ "Usage:"
    end

    test "shows flags for learn command" do
      text = Help.render("learn")
      assert text =~ "--subject"
    end

    test "shows examples when present" do
      text = Help.render("learn")
      assert text =~ "Example"
    end
  end

  describe "render/1 unknown command" do
    test "shows error and global help" do
      text = Help.render("nonexistent")
      assert text =~ "Unknown command: nonexistent"
      assert text =~ "Usage:"
    end
  end

  describe "help spec coverage" do
    test "every dispatcher command has a help spec" do
      for cmd <- Dispatcher.commands() do
        text = Help.render(cmd)
        refute text =~ "Unknown command", "missing help spec for: #{cmd}"
      end
    end
  end
end
