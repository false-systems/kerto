defmodule Kerto.Interface.Command.TrackEditTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Command.TrackEdit

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_track_edit_engine, decay_interval_ms: :timer.hours(1)}
    )

    %{engine: :test_track_edit_engine}
  end

  test "tracks a file edit", %{engine: engine} do
    resp = TrackEdit.execute(engine, %{file: "auth.ex", session: "s1"})
    assert resp.ok

    sessions = Kerto.Engine.list_sessions(engine)
    assert "s1" in sessions
  end

  test "uses default session when not specified", %{engine: engine} do
    resp = TrackEdit.execute(engine, %{file: "auth.ex"})
    assert resp.ok

    sessions = Kerto.Engine.list_sessions(engine)
    assert "default" in sessions
  end

  test "returns error when file is missing", %{engine: engine} do
    resp = TrackEdit.execute(engine, %{})
    refute resp.ok
    assert resp.error =~ "file"
  end
end
