defmodule Kerto.Interface.Protocol do
  @moduledoc "Shared JSON wire format for daemon socket and MCP transports."

  alias Kerto.Interface.Response

  @atom_fields ~w(kind relation source_kind target_kind subject_kind format)

  @known_arg_keys ~w(
    kind name depth min_weight subject target relation
    subject_kind target_kind confidence evidence type data
    source format factor node source_kind target_kind
    json summary files
  )a

  @spec encode_response(Response.t()) :: String.t()
  def encode_response(%Response{ok: true, data: data}) do
    Jason.encode!(%{ok: true, data: serialize(data)})
  end

  def encode_response(%Response{ok: false, error: error}) do
    Jason.encode!(%{ok: false, error: to_string(error)})
  end

  @spec decode_args(map()) :: map()
  def decode_args(args) when is_map(args) do
    args |> atomize_keys() |> atomize_known_values()
  end

  @spec decode_request(String.t()) :: {String.t(), map()} | {:error, String.t()}
  def decode_request(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, %{"command" => command} = payload} ->
        args =
          payload
          |> Map.get("args", %{})
          |> atomize_keys()
          |> atomize_known_values()

        {command, args}

      {:ok, _} ->
        {:error, "missing \"command\" field"}

      {:error, _} ->
        {:error, "invalid JSON"}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        case Enum.find(@known_arg_keys, &(Atom.to_string(&1) == k)) do
          nil -> {k, v}
          atom_key -> {atom_key, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp atomize_known_values(args) do
    Enum.reduce(@atom_fields, args, fn field, acc ->
      key = String.to_atom(field)

      case Map.get(acc, key) do
        val when is_binary(val) ->
          safe_val =
            try do
              String.to_existing_atom(val)
            rescue
              ArgumentError -> val
            end

          Map.put(acc, key, safe_val)

        _ ->
          acc
      end
    end)
  end

  defp serialize(:ok), do: "ok"
  defp serialize(val) when is_atom(val), do: Atom.to_string(val)

  defp serialize(val) when is_map(val) do
    Map.new(val, fn {k, v} -> {serialize_key(k), serialize(v)} end)
  end

  defp serialize(val) when is_list(val), do: Enum.map(val, &serialize/1)
  defp serialize(val), do: val

  defp serialize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp serialize_key(key), do: key
end
