defmodule Kerto.Interface.ContextWriterTest do
  use ExUnit.Case, async: false

  alias Kerto.Interface.ContextWriter
  alias Kerto.Ingestion.{Occurrence, Source}

  @test_dir System.tmp_dir!() |> Path.join("kerto_cw_test_#{System.unique_integer([:positive])}")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    path = Path.join(@test_dir, "CONTEXT.md")

    engine = :"test_cw_engine_#{System.unique_integer([:positive])}"

    start_supervised!({Kerto.Engine, name: engine, decay_interval_ms: :timer.hours(1)})

    writer =
      start_supervised!(
        {ContextWriter,
         engine: engine,
         path: path,
         debounce_ms: 10,
         name: :"test_cw_#{System.unique_integer([:positive])}"}
      )

    %{engine: engine, writer: writer, path: path}
  end

  test "renders empty context when graph is empty", %{writer: writer, path: path} do
    ContextWriter.notify_mutation(writer)
    Process.sleep(50)
    assert File.exists?(path)
    content = File.read!(path)
    assert content =~ "No knowledge recorded yet"
  end

  test "renders node context after learning", %{engine: engine, writer: writer, path: path} do
    learn(engine, "auth.go handles auth", "auth.go")
    ContextWriter.notify_mutation(writer)
    Process.sleep(50)
    content = File.read!(path)
    assert content =~ "auth.go"
    assert content =~ "Kerto Knowledge Context"
  end

  test "debounces multiple rapid mutations", %{engine: engine, writer: writer, path: path} do
    learn(engine, "first", "a.go")
    ContextWriter.notify_mutation(writer)
    learn(engine, "second", "b.go")
    ContextWriter.notify_mutation(writer)
    learn(engine, "third", "c.go")
    ContextWriter.notify_mutation(writer)
    Process.sleep(50)
    content = File.read!(path)
    assert content =~ "c.go"
  end

  test "render_full_context/1 is a pure function" do
    graph = Kerto.Graph.Graph.new()
    content = ContextWriter.render_full_context(graph)
    assert content =~ "No knowledge recorded yet"
  end

  test "render_full_context/1 with nodes" do
    {graph, _} =
      Kerto.Graph.Graph.upsert_node(Kerto.Graph.Graph.new(), :file, "auth.go", 0.8, "01TEST")

    content = ContextWriter.render_full_context(graph)
    assert content =~ "auth.go"
  end

  test "creates parent directory if missing", %{engine: engine} do
    nested = Path.join([@test_dir, "deep", "nested", "CONTEXT.md"])

    writer2 =
      start_supervised!(
        {ContextWriter, engine: engine, path: nested, debounce_ms: 10, name: :test_cw_nested},
        id: :nested_writer
      )

    ContextWriter.notify_mutation(writer2)
    Process.sleep(50)
    assert File.exists?(nested)
  end

  test "flushes pending render on terminate", %{engine: engine, path: path} do
    writer2 =
      start_supervised!(
        {ContextWriter,
         engine: engine, path: path, debounce_ms: :timer.hours(1), name: :test_cw_flush},
        id: :flush_writer
      )

    learn(engine, "flush test", "flush.go")
    ContextWriter.notify_mutation(writer2)
    stop_supervised!(:flush_writer)

    assert File.exists?(path)
    assert File.read!(path) =~ "flush.go"
  end

  test "terminate without pending timer is clean", %{engine: engine} do
    start_supervised!(
      {ContextWriter,
       engine: engine,
       path: Path.join(@test_dir, "no_timer.md"),
       debounce_ms: 10,
       name: :test_cw_no_timer},
      id: :no_timer_writer
    )

    stop_supervised!(:no_timer_writer)
  end

  test "limits to top 20 nodes by relevance" do
    graph =
      Enum.reduce(1..25, Kerto.Graph.Graph.new(), fn i, g ->
        {g, _} = Kerto.Graph.Graph.upsert_node(g, :file, "file_#{i}.go", 0.8, "01TEST#{i}")
        g
      end)

    content = ContextWriter.render_full_context(graph)
    node_count = content |> String.split("(file)") |> length() |> Kernel.-(1)
    assert node_count == 20
  end

  defp learn(engine, evidence, subject) do
    occ =
      Occurrence.new(
        "context.learning",
        %{
          subject_kind: :file,
          subject_name: subject,
          target_kind: :concept,
          target_name: "knowledge",
          relation: :learned,
          evidence: evidence
        },
        Source.new("test", "test", Kerto.Interface.ULID.generate())
      )

    Kerto.Engine.ingest(engine, occ)
  end
end
