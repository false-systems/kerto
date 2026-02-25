defmodule Kerto.Interface.Command.Observe do
  @moduledoc "Records a session summary as an `agent.session_end` occurrence."

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    case Map.get(args, :summary) do
      nil ->
        Response.error("missing required argument: summary")

      summary ->
        files = normalize_files(Map.get(args, :files, []))
        data = %{summary: summary, files: files}
        source = Source.new("kerto", "cli", ULID.generate())
        occurrence = Occurrence.new("agent.session_end", data, source)
        Kerto.Engine.ingest(engine, occurrence)
        Response.success(:ok)
    end
  end

  defp normalize_files(files) when is_list(files), do: files
  defp normalize_files(files) when is_binary(files), do: String.split(files, ",", trim: true)
  defp normalize_files(_), do: []
end
