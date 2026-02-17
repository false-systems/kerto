defmodule Kerto.Rendering.Context do
  @moduledoc """
  Intermediate data structure for rendering.

  Bundles the focal node, its relationships, and a lookup map
  from node IDs to Node structs. Renderer consumes this to produce
  natural language — no graph access needed at render time.
  """

  alias Kerto.Graph.{Node, Relationship}

  @enforce_keys [:node, :relationships, :node_lookup]
  defstruct [:node, :relationships, :node_lookup]

  @type t :: %__MODULE__{
          node: Node.t(),
          relationships: [Relationship.t()],
          node_lookup: %{String.t() => Node.t()}
        }

  @spec new(Node.t(), [Relationship.t()], %{String.t() => Node.t()}) :: t()
  def new(%Node{} = node, relationships, node_lookup)
      when is_list(relationships) and is_map(node_lookup) do
    %__MODULE__{node: node, relationships: relationships, node_lookup: node_lookup}
  end
end
