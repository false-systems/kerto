defmodule Kerto.Interface.Command.TeamTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Team

  @engine :test_team_engine

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    # Use a temp dir for .kerto to avoid polluting the real one
    tmp_dir =
      Path.join(System.tmp_dir!(), "kerto_team_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    old_cwd = File.cwd!()
    File.cd!(tmp_dir)

    on_exit(fn ->
      File.cd!(old_cwd)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  describe "init action" do
    test "creates CA key and cert" do
      resp = Team.execute(@engine, %{action: "init", name: "test-team"})
      assert resp.ok
      assert resp.data =~ "Team CA created"
      assert File.exists?(".kerto/ca.key")
      assert File.exists?(".kerto/ca.crt")
    end

    test "rejects duplicate init" do
      Team.execute(@engine, %{action: "init"})
      resp = Team.execute(@engine, %{action: "init"})
      refute resp.ok
      assert resp.error =~ "already exists"
    end
  end

  describe "join action" do
    test "creates node key and CSR" do
      resp = Team.execute(@engine, %{action: "join", name: "dev-a"})
      assert resp.ok
      assert resp.data =~ "CSR created"
      assert File.exists?(".kerto/node.key")
      assert File.exists?(".kerto/node.csr")
    end
  end

  describe "sign action" do
    test "signs a CSR with the CA" do
      Team.execute(@engine, %{action: "init", name: "test-team"})
      Team.execute(@engine, %{action: "join", name: "dev-a"})
      resp = Team.execute(@engine, %{action: "sign", csr: ".kerto/node.csr"})
      assert resp.ok
      assert resp.data =~ "Signed certificate"
      assert File.exists?(".kerto/node.crt")
    end

    test "returns error without csr path" do
      resp = Team.execute(@engine, %{action: "sign"})
      refute resp.ok
      assert resp.error =~ "--csr"
    end
  end

  describe "list action" do
    test "lists team after init" do
      Team.execute(@engine, %{action: "init", name: "test-team"})
      resp = Team.execute(@engine, %{action: "list"})
      assert resp.ok
      assert resp.data =~ "Team:"
    end

    test "returns error without CA" do
      resp = Team.execute(@engine, %{action: "list"})
      refute resp.ok
      assert resp.error =~ "no team CA"
    end
  end

  describe "missing action" do
    test "returns error" do
      resp = Team.execute(@engine, %{})
      refute resp.ok
      assert resp.error =~ "specify --action"
    end
  end
end
