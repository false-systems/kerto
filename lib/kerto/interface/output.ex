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

  defp print_text(%Response{ok: true, data: %{node: _, relationships: _, rendered: text}}) do
    IO.puts(text)
  end

  defp print_text(%Response{ok: true, data: %{nodes: nodes}}) when is_list(nodes) do
    case nodes do
      [] ->
        IO.puts("No nodes found.")

      nodes ->
        IO.puts("#{length(nodes)} node(s):")

        Enum.each(nodes, fn n ->
          pin = if n.pinned, do: " [pinned]", else: ""

          IO.puts(
            "  #{n.kind}:#{n.name}  relevance=#{format_float(n.relevance)}  obs=#{n.observations}#{pin}"
          )
        end)
    end
  end

  defp print_text(%Response{ok: true, data: %{relationships: rels}}) when is_list(rels) do
    case rels do
      [] ->
        IO.puts("No relationships found.")

      rels ->
        IO.puts("#{length(rels)} relationship(s):")

        Enum.each(rels, fn r ->
          pin = if r.pinned, do: " [pinned]", else: ""
          src = r[:source_name] || short_id(r.source)
          tgt = r[:target_name] || short_id(r.target)

          IO.puts(
            "  #{src} --#{r.relation}--> #{tgt}  weight=#{format_float(r.weight)}  obs=#{r.observations}#{pin}"
          )
        end)
    end
  end

  defp print_text(%Response{ok: true, data: data}) when is_map(data) do
    IO.puts(Jason.encode!(serialize(data), pretty: true))
  end

  defp print_text(%Response{ok: true, data: data}) do
    IO.puts(inspect(data))
  end

  defp serialize(val) when val in [nil, true, false], do: val
  defp serialize(val) when is_atom(val), do: Atom.to_string(val)

  defp serialize(val) when is_map(val),
    do: Map.new(val, fn {k, v} -> {serialize_key(k), serialize(v)} end)

  defp serialize(val) when is_list(val), do: Enum.map(val, &serialize/1)
  defp serialize(val), do: val

  defp serialize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp serialize_key(key), do: key

  defp format_float(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 3)
  defp format_float(f), do: to_string(f)

  defp short_id(id) when is_binary(id) and byte_size(id) > 8,
    do: String.slice(id, 0, 8) <> ".."

  defp short_id(id), do: id
end
