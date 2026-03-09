defmodule Kerto.Interface.Command.ScanTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.Scan

  @engine :test_scan_engine

  setup do
    start_supervised!(
      {Kerto.Engine,
       name: @engine,
       decay_interval_ms: :timer.hours(1),
       plugins: [],
       plugin_interval_ms: :infinity}
    )

    :ok
  end

  describe "execute/2" do
    test "returns success" do
      resp = Scan.execute(@engine, %{})
      assert resp.ok
      assert resp.data =~ "scan complete"
    end
  end
end
