defmodule Kerto.Interface.Validate do
  @moduledoc """
  Input validation for the command layer.

  Converts untrusted input (strings, wrong types) into domain-safe values
  or returns `{:error, reason}`. Commands use these to guard the boundary
  between transports and domain code.
  """

  alias Kerto.Graph.{NodeKind, RelationType}

  @spec relation(term()) :: {:ok, atom()} | {:error, String.t()}
  def relation(val) when is_atom(val) do
    if RelationType.valid?(val), do: {:ok, val}, else: {:error, "unknown relation: #{val}"}
  end

  def relation(val) when is_binary(val) do
    match = Enum.find(RelationType.all(), fn r -> Atom.to_string(r) == val end)
    if match, do: {:ok, match}, else: {:error, "unknown relation: #{val}"}
  end

  def relation(_), do: {:error, "relation must be a string or atom"}

  @spec node_kind(term()) :: {:ok, atom()} | {:error, String.t()}
  def node_kind(val) when is_atom(val) do
    if NodeKind.valid?(val), do: {:ok, val}, else: {:error, "unknown node kind: #{val}"}
  end

  def node_kind(val) when is_binary(val) do
    match = Enum.find(NodeKind.all(), fn k -> Atom.to_string(k) == val end)
    if match, do: {:ok, match}, else: {:error, "unknown node kind: #{val}"}
  end

  def node_kind(_), do: {:error, "node kind must be a string or atom"}

  @spec float_val(term(), String.t()) :: {:ok, float()} | {:error, String.t()}
  def float_val(val, _name) when is_float(val), do: {:ok, val}
  def float_val(val, _name) when is_integer(val), do: {:ok, val * 1.0}
  def float_val(_, name), do: {:error, "#{name} must be a number"}

  @spec integer_val(term(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def integer_val(val, _name) when is_integer(val), do: {:ok, val}
  def integer_val(_, name), do: {:error, "#{name} must be an integer"}
end
