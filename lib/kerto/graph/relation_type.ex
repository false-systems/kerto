defmodule Kerto.Graph.RelationType do
  @moduledoc """
  Classification of a Relationship between Knowledge Nodes.

  Value object — immutable, equality by value.
  """

  @types [
    :breaks,
    :caused_by,
    :triggers,
    :depends_on,
    :deployed_to,
    :part_of,
    :learned,
    :decided,
    :tried_failed,
    :often_changes_with,
    :edited_with
  ]

  @spec all() :: [atom()]
  def all, do: @types

  @spec valid?(term()) :: boolean()
  def valid?(type) when type in @types, do: true
  def valid?(_), do: false

  @spec inverse_label(atom()) :: String.t()
  def inverse_label(:breaks), do: "broken by"
  def inverse_label(:caused_by), do: "causes"
  def inverse_label(:triggers), do: "triggered by"
  def inverse_label(:depends_on), do: "depended on by"
  def inverse_label(:part_of), do: "contains"
  def inverse_label(:deployed_to), do: "deploys"
  def inverse_label(type) when type in @types, do: Atom.to_string(type)
end
