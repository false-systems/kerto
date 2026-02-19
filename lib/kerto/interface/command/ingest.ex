defmodule Kerto.Interface.Command.Ingest do
  @moduledoc """
  Ingests a raw FALSE Protocol occurrence from a JSON map.
  """

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, type} <- require_arg(args, :type) do
      data = Map.get(args, :data, %{})
      source = build_source(args)
      occurrence = Occurrence.new(type, data, source)
      Kerto.Engine.ingest(engine, occurrence)
      Response.success(:ok)
    end
  end

  defp build_source(args) do
    system = get_in(args, [:source, :system]) || "external"
    agent = get_in(args, [:source, :agent]) || "unknown"
    ulid = get_in(args, [:source, :ulid]) || ULID.generate()
    Source.new(system, agent, ulid)
  end

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
