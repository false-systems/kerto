defmodule Kerto.Plugin.ClaudeTest do
  use ExUnit.Case, async: true

  alias Kerto.Plugin.Claude
  alias Kerto.Ingestion.Occurrence

  @moduletag :tmp_dir

  describe "agent_name/0" do
    test "returns claude" do
      assert Claude.agent_name() == "claude"
    end
  end

  describe "scan/2 file reads" do
    test "extracts Read tool_use as agent.file_read", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Read", %{"file_path" => "/app/lib/auth.ex"}),
        tool_result("t1", false, "file contents")
      ])

      [occ] = Claude.scan(nil, projects_dir: tmp_dir)
      assert %Occurrence{type: "agent.file_read"} = occ
      assert occ.data.file =~ "auth.ex"
    end

    test "extracts Edit tool_use as agent.file_read", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Edit", %{
          "file_path" => "/app/lib/router.ex",
          "old_string" => "old",
          "new_string" => "new"
        }),
        tool_result("t1", false, "OK")
      ])

      [occ] = Claude.scan(nil, projects_dir: tmp_dir)
      assert occ.data.file =~ "router.ex"
    end

    test "extracts Write tool_use as agent.file_read", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Write", %{"file_path" => "/app/lib/new.ex", "content" => "code"}),
        tool_result("t1", false, "OK")
      ])

      [occ] = Claude.scan(nil, projects_dir: tmp_dir)
      assert occ.data.file =~ "new.ex"
    end

    test "deduplicates same file path", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Read", %{"file_path" => "/app/lib/auth.ex"}),
        tool_result("t1", false, "ok"),
        tool_use("t2", "Read", %{"file_path" => "/app/lib/auth.ex"}),
        tool_result("t2", false, "ok")
      ])

      occs = Claude.scan(nil, projects_dir: tmp_dir)
      file_reads = Enum.filter(occs, &(&1.type == "agent.file_read"))
      assert length(file_reads) == 1
    end

    test "skips non-file tools like Grep and Bash", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Grep", %{"pattern" => "foo"}),
        tool_result("t1", false, "results"),
        tool_use("t2", "Bash", %{"command" => "ls"}),
        tool_result("t2", false, "files")
      ])

      occs = Claude.scan(nil, projects_dir: tmp_dir)
      assert Enum.filter(occs, &(&1.type == "agent.file_read")) == []
    end
  end

  describe "scan/2 tool errors" do
    test "extracts errored tool_result as agent.tool_error", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Bash", %{"command" => "make test"}),
        tool_result("t1", true, "Exit code 1\ncompilation failed")
      ])

      [occ] = Claude.scan(nil, projects_dir: tmp_dir)
      assert occ.type == "agent.tool_error"
      assert occ.data.tool == "Bash"
      assert occ.data.error =~ "compilation failed"
    end

    test "does not emit for non-error results", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Bash", %{"command" => "echo hi"}),
        tool_result("t1", false, "hi")
      ])

      occs = Claude.scan(nil, projects_dir: tmp_dir)
      assert Enum.filter(occs, &(&1.type == "agent.tool_error")) == []
    end
  end

  describe "scan/2 multiple conversations" do
    test "reads from multiple JSONL files", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(project)

      write_jsonl(project, "conv1.jsonl", [
        tool_use("t1", "Read", %{"file_path" => "/app/a.ex"}),
        tool_result("t1", false, "ok")
      ])

      write_jsonl(project, "conv2.jsonl", [
        tool_use("t1", "Read", %{"file_path" => "/app/b.ex"}),
        tool_result("t1", false, "ok")
      ])

      occs = Claude.scan(nil, projects_dir: tmp_dir)
      files = Enum.map(occs, & &1.data.file)
      assert Enum.any?(files, &(&1 =~ "a.ex"))
      assert Enum.any?(files, &(&1 =~ "b.ex"))
    end
  end

  describe "scan/2 resilience" do
    test "handles malformed JSON lines", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(project)

      File.write!(Path.join(project, "conv.jsonl"), """
      not valid json
      #{Jason.encode!(tool_use("t1", "Read", %{"file_path" => "/app/x.ex"}))}
      also broken {{{
      #{Jason.encode!(tool_result("t1", false, "ok"))}
      """)

      occs = Claude.scan(nil, projects_dir: tmp_dir)
      assert length(occs) == 1
    end

    test "returns empty when projects_dir missing" do
      assert Claude.scan(nil, projects_dir: "/nonexistent") == []
    end

    test "returns empty when no JSONL files", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(project)
      assert Claude.scan(nil, projects_dir: tmp_dir) == []
    end
  end

  describe "scan/2 last_sync filtering" do
    test "skips files older than last_sync", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(project)
      path = Path.join(project, "old.jsonl")

      write_jsonl(project, "old.jsonl", [
        tool_use("t1", "Read", %{"file_path" => "/app/old.ex"}),
        tool_result("t1", false, "ok")
      ])

      # Set mtime to year 2020
      File.touch!(path, {{2020, 1, 1}, {0, 0, 0}})

      future_ulid = Kerto.Interface.ULID.generate()
      assert Claude.scan(future_ulid, projects_dir: tmp_dir) == []
    end

    test "includes files newer than last_sync", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Read", %{"file_path" => "/app/new.ex"}),
        tool_result("t1", false, "ok")
      ])

      # Very old ULID (timestamp near 0)
      old_ulid = String.duplicate("0", 26)
      occs = Claude.scan(old_ulid, projects_dir: tmp_dir)
      assert length(occs) == 1
    end
  end

  describe "source provenance" do
    test "occurrences have claude source", %{tmp_dir: tmp_dir} do
      write_conv(tmp_dir, [
        tool_use("t1", "Read", %{"file_path" => "/app/x.ex"}),
        tool_result("t1", false, "ok")
      ])

      [occ] = Claude.scan(nil, projects_dir: tmp_dir)
      assert occ.source.system == "claude"
      assert occ.source.agent == "claude"
      assert is_binary(occ.source.ulid)
    end
  end

  # --- Helpers ---

  defp write_conv(tmp_dir, lines) do
    project = Path.join(tmp_dir, "proj")
    File.mkdir_p!(project)
    write_jsonl(project, "test.jsonl", lines)
  end

  defp write_jsonl(dir, filename, lines) do
    content = lines |> Enum.map(&Jason.encode!/1) |> Enum.join("\n")
    File.write!(Path.join(dir, filename), content <> "\n")
  end

  defp tool_use(id, name, input) do
    %{
      "type" => "assistant",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "message" => %{
        "role" => "assistant",
        "content" => [%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}]
      }
    }
  end

  defp tool_result(tool_use_id, is_error, content) do
    %{
      "type" => "user",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "message" => %{
        "role" => "user",
        "content" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => tool_use_id,
            "is_error" => is_error,
            "content" => content
          }
        ]
      }
    }
  end
end
