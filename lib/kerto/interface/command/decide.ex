defmodule Kerto.Interface.Command.Decide do
  @moduledoc """
  Records an architectural decision as a `context.decision` occurrence.
  """

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, evidence} <- require_arg(args, :evidence),
         {:ok, subject} <- require_arg(args, :subject),
         {:ok, target} <- require_arg(args, :target) do
      data = %{
        subject_name: subject,
        subject_kind: Map.get(args, :subject_kind, :module),
        target_name: target,
        target_kind: Map.get(args, :target_kind, :decision),
        evidence: evidence,
        confidence: Map.get(args, :confidence, 0.9)
      }

      source = Source.new("kerto", "cli", ULID.generate())
      occurrence = Occurrence.new("context.decision", data, source)
      Kerto.Engine.ingest(engine, occurrence)
      Response.success(:ok)
    end
  end

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
