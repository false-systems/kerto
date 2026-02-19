defmodule Kerto.Interface.ULID do
  @moduledoc """
  Minimal ULID generator for the interface boundary.

  Generates time-sortable, unique identifiers for occurrences
  created at the CLI/MCP boundary. Domain code receives ULIDs
  as opaque strings — only this module generates them.
  """

  @crockford ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @spec generate() :: String.t()
  def generate do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(10)
    encode_timestamp(timestamp, 10) <> encode_random(random)
  end

  defp encode_timestamp(ts, count) do
    encode_timestamp(ts, count, [])
    |> IO.iodata_to_binary()
  end

  defp encode_timestamp(_ts, 0, acc), do: acc

  defp encode_timestamp(ts, remaining, acc) do
    char = Enum.at(@crockford, rem(ts, 32))
    encode_timestamp(div(ts, 32), remaining - 1, [char | acc])
  end

  defp encode_random(<<bytes::binary-10>>) do
    encode_random_bits(bytes, 16, [])
    |> IO.iodata_to_binary()
  end

  defp encode_random_bits(_bytes, 0, acc), do: Enum.reverse(acc)

  defp encode_random_bits(bytes, remaining, acc) do
    bit_offset = (16 - remaining) * 5
    <<_::size(bit_offset), value::5, _::bits>> = <<bytes::binary, 0>>
    char = Enum.at(@crockford, value)
    encode_random_bits(bytes, remaining - 1, [char | acc])
  end
end
