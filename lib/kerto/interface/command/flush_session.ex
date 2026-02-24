defmodule Kerto.Interface.Command.FlushSession do
  @moduledoc "Flushes session buffer and ingests co-edit relationships."

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    session = Map.get(args, :session, "default")

    case Kerto.Engine.flush_session(engine, session) do
      {:ok, %{files: [_ | _] = files, agent: agent}} ->
        source = Source.new("kerto", agent, ULID.generate())
        data = %{files: files, agent: agent}
        occ = Occurrence.new("agent.session_edits", data, source)
        Kerto.Engine.ingest(engine, occ)
        Response.success("flushed #{length(files)} files from session #{session}")

      {:ok, _} ->
        Response.success("session #{session} had no files")

      {:error, :not_found} ->
        Response.success("no active session #{session}")
    end
  end
end
