defmodule Kerto.Interface.Output do
  @moduledoc """
  Formats `Response.t()` for terminal output.

  Text mode: human-readable. JSON mode: machine-readable via Jason.
  """

  alias Kerto.Interface.Response

  @spec print(Response.t(), :text | :json) :: :ok
  def print(response, :json), do: print_json(response)
  def print(response, :text), do: print_text(response)

  defp print_json(%Response{ok: true, data: data}) do
    IO.puts(Jason.encode!(%{ok: true, data: serialize(data)}))
  end

  defp print_json(%Response{ok: false, error: error}) do
    IO.puts(Jason.encode!(%{ok: false, error: serialize(error)}))
  end

  defp print_text(%Response{ok: false, error: error}) do
    IO.puts("Error: #{error}")
  end

  defp print_text(%Response{ok: true, data: :ok}) do
    IO.puts("OK")
  end

  defp print_text(%Response{ok: true, data: data}) when is_binary(data) do
    IO.puts(data)
  end

  defp print_text(%Response{ok: true, data: %{nodes: n, relationships: r, occurrences: o}})
       when is_integer(n) do
    IO.puts("Nodes: #{n}  Relationships: #{r}  Occurrences: #{o}")
  end

  defp print_text(%Response{ok: true, data: data}) when is_map(data) do
    IO.puts(Jason.encode!(serialize(data), pretty: true))
  end

  defp print_text(%Response{ok: true, data: data}) do
    IO.puts(inspect(data))
  end

  defp serialize(val) when is_atom(val), do: Atom.to_string(val)

  defp serialize(val) when is_map(val),
    do: Map.new(val, fn {k, v} -> {serialize_key(k), serialize(v)} end)

  defp serialize(val) when is_list(val), do: Enum.map(val, &serialize/1)
  defp serialize(val), do: val

  defp serialize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp serialize_key(key), do: key
end
