defmodule Kerto.Interface.Command.Ingest do
  @moduledoc """
  Ingests a raw FALSE Protocol occurrence from a JSON map.
  """

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, type} <- require_arg(args, :type),
         {:ok, data} <- parse_data(args) do
      source = build_source(args)
      occurrence = Occurrence.new(type, atomize_data(data), source)
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

  defp parse_data(args) do
    case Map.get(args, :data) do
      nil ->
        {:ok, %{}}

      data when is_map(data) ->
        {:ok, data}

      data when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
          _ -> Response.error("--data must be valid JSON object")
        end
    end
  end

  defp atomize_data(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_data(v)}
      {k, v} -> {k, atomize_data(v)}
    end)
  end

  defp atomize_data(data) when is_list(data), do: Enum.map(data, &atomize_data/1)
  defp atomize_data(data), do: data

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
