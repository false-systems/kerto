defmodule Kerto.Ingestion.ExtractionOp do
  @moduledoc """
  Typed operations describing graph mutations.

  Extractors return these instead of mutating the graph directly.
  Level 2 applies them using `Identity.compute_id/2` and `Graph.upsert_node/5`.

  Operations carry `kind + name` (not pre-computed IDs), keeping
  Level 1 extractors decoupled from identity computation details.
  """

  @type upsert_node :: {:upsert_node, node_attrs()}
  @type upsert_relationship :: {:upsert_relationship, relationship_attrs()}
  @type weaken_relationship :: {:weaken_relationship, weaken_attrs()}
  @type t :: upsert_node() | upsert_relationship() | weaken_relationship()

  @type node_attrs :: %{
          kind: atom(),
          name: String.t(),
          confidence: float()
        }

  @type relationship_attrs :: %{
          source_kind: atom(),
          source_name: String.t(),
          relation: atom(),
          target_kind: atom(),
          target_name: String.t(),
          confidence: float(),
          evidence: String.t()
        }

  @type weaken_attrs :: %{
          source_kind: atom(),
          source_name: String.t(),
          relation: atom(),
          target_kind: atom(),
          target_name: String.t(),
          factor: float()
        }
end
