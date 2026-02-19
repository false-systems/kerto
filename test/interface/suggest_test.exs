defmodule Kerto.Interface.SuggestTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.Suggest
  alias Kerto.Ingestion.{Occurrence, Source}

  setup do
    start_supervised!(
      {Kerto.Engine, name: :test_suggest_engine, decay_interval_ms: :timer.hours(1)}
    )

    for file <- ["auth.go", "auth_test.go", "oauth.go", "session.go", "handler.go"] do
      occ =
        Occurrence.new(
          "ci.run.failed",
          %{files: [file], task: "test"},
          Source.new("test", "ci", "01J#{file}")
        )

      Kerto.Engine.ingest(:test_suggest_engine, occ)
    end

    %{engine: :test_suggest_engine}
  end

  test "similar_names returns matches above threshold", %{engine: engine} do
    results = Suggest.similar_names(engine, :file, "auth")
    assert length(results) > 0
    assert "auth.go" in results
  end

  test "similar_names returns empty for no matches", %{engine: engine} do
    results = Suggest.similar_names(engine, :file, "zzzzzzzzz")
    assert results == []
  end

  test "similar_names respects kind filter", %{engine: engine} do
    results = Suggest.similar_names(engine, :module, "auth")
    assert results == []
  end

  test "similar_names respects limit", %{engine: engine} do
    results = Suggest.similar_names(engine, :file, "auth", 1)
    assert length(results) <= 1
  end
end
