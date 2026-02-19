defmodule Kerto.Interface.Parser do
  @moduledoc """
  Translates CLI argv into `{command, args_map}`.

  Each command defines its own switches. The parser converts CLI strings
  (kebab-case flags, string values) into the atom-keyed maps that commands expect.
  """

  @global_switches [json: :boolean]

  @command_switches %{
    "context" => [kind: :string, depth: :integer, min_weight: :float],
    "learn" => [
      subject: :string,
      target: :string,
      relation: :string,
      subject_kind: :string,
      target_kind: :string,
      confidence: :float
    ],
    "decide" => [
      subject: :string,
      target: :string,
      subject_kind: :string,
      target_kind: :string,
      confidence: :float
    ],
    "ingest" => [type: :string],
    "graph" => [format: :string],
    "decay" => [factor: :float],
    "weaken" => [
      source: :string,
      target: :string,
      relation: :string,
      source_kind: :string,
      target_kind: :string,
      factor: :float
    ],
    "delete" => [
      node: :string,
      kind: :string,
      source: :string,
      target: :string,
      relation: :string,
      source_kind: :string,
      target_kind: :string
    ]
  }

  @atom_fields ~w(kind format relation source_kind target_kind subject_kind)a

  @spec parse([String.t()]) :: {String.t(), map()} | {:error, String.t()}
  def parse([]), do: {:error, "no command given"}

  def parse([command | rest]) do
    switches = Map.get(@command_switches, command, []) ++ @global_switches

    aliases =
      Enum.flat_map(switches, fn {key, _type} ->
        kebab = key |> Atom.to_string() |> String.replace("_", "-")

        if kebab != Atom.to_string(key) do
          [{String.to_atom(kebab), key}]
        else
          []
        end
      end)

    {parsed, positional, _invalid} =
      OptionParser.parse(rest, strict: switches, aliases: aliases)

    args =
      parsed
      |> Map.new()
      |> add_positional(command, positional)
      |> atomize_fields()

    {command, args}
  end

  defp add_positional(args, "context", [name | _]), do: Map.put(args, :name, name)
  defp add_positional(args, "learn", [evidence | _]), do: Map.put(args, :evidence, evidence)
  defp add_positional(args, "decide", [evidence | _]), do: Map.put(args, :evidence, evidence)
  defp add_positional(args, _command, _positional), do: args

  defp atomize_fields(args) do
    Enum.reduce(@atom_fields, args, fn field, acc ->
      case Map.get(acc, field) do
        nil -> acc
        val when is_binary(val) -> Map.put(acc, field, String.to_atom(val))
        _ -> acc
      end
    end)
  end
end
