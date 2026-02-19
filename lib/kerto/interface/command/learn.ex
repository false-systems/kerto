defmodule Kerto.Interface.Command.Learn do
  @moduledoc """
  Records a learning by constructing a `context.learning` occurrence and ingesting it.

  With `--target`: creates a full learning occurrence (subject → relation → target).
  Without `--target`: upserts only the subject node via direct ops.
  """

  alias Kerto.Ingestion.{Occurrence, Source}
  alias Kerto.Interface.{Response, ULID, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    with {:ok, evidence} <- require_arg(args, :evidence),
         {:ok, subject} <- require_arg(args, :subject),
         {:ok, subject_kind} <- Validate.node_kind(Map.get(args, :subject_kind, :file)) do
      case Map.get(args, :target) do
        nil ->
          ingest_subject_only(engine, subject, subject_kind, evidence)

        target ->
          build_and_ingest_learning(engine, args, subject, subject_kind, target, evidence)
      end
    else
      %Response{ok: false} = resp -> resp
      {:error, reason} -> Response.error(reason)
    end
  end

  defp build_and_ingest_learning(engine, args, subject, subject_kind, target, evidence) do
    with {:ok, target_kind} <- Validate.node_kind(Map.get(args, :target_kind, :concept)),
         {:ok, relation} <- Validate.relation(Map.get(args, :relation, :learned)),
         {:ok, confidence} <- Validate.float_val(Map.get(args, :confidence, 0.8), "confidence") do
      ingest_learning(engine, %{
        subject_name: subject,
        subject_kind: subject_kind,
        target_name: target,
        target_kind: target_kind,
        relation: relation,
        evidence: evidence,
        confidence: confidence
      })
    else
      {:error, reason} -> Response.error(reason)
    end
  end

  defp ingest_learning(engine, data) do
    source = Source.new("kerto", "cli", ULID.generate())
    occurrence = Occurrence.new("context.learning", data, source)
    Kerto.Engine.ingest(engine, occurrence)
    Response.success(:ok)
  end

  defp ingest_subject_only(engine, subject, kind, _evidence) do
    ulid = ULID.generate()
    ops = [{:upsert_node, %{kind: kind, name: subject, confidence: 0.8}}]
    Kerto.Engine.Store.apply_ops(child_store(engine), ops, ulid)
    Response.success(:ok)
  end

  defp child_store(engine), do: :"#{engine}.store"

  defp require_arg(args, key) do
    case Map.get(args, key) do
      nil -> Response.error("missing required argument: #{key}")
      val -> {:ok, val}
    end
  end
end
