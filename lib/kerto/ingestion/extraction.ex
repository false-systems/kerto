defmodule Kerto.Ingestion.Extraction do
  @moduledoc """
  Dispatches occurrences to the appropriate extractor.

  Pattern-matches on `occurrence.type` and delegates to the
  corresponding extractor module. Returns `[]` for unknown types,
  making this composable with no error tuples.
  """

  alias Kerto.Ingestion.{Extractor, Occurrence}

  @spec extract(Occurrence.t()) :: [Kerto.Ingestion.ExtractionOp.t()]
  def extract(%Occurrence{type: "vcs.commit"} = occ), do: Extractor.Commit.extract(occ)
  def extract(%Occurrence{type: "ci.run.failed"} = occ), do: Extractor.CiFailure.extract(occ)
  def extract(%Occurrence{type: "ci.run.passed"} = occ), do: Extractor.CiSuccess.extract(occ)
  def extract(%Occurrence{type: "context.learning"} = occ), do: Extractor.Learning.extract(occ)
  def extract(%Occurrence{type: "context.decision"} = occ), do: Extractor.Decision.extract(occ)
  def extract(%Occurrence{}), do: []
end
