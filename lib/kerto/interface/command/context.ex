defmodule Kerto.Interface.Command.Context do
  @moduledoc """
  Queries the knowledge graph for an entity and returns rendered context.
  """

  alias Kerto.Interface.{Response, Suggest, Validate}

  @spec execute(atom(), map()) :: Response.t()
  def execute(engine, args) do
    name = Map.get(args, :name)

    if is_nil(name) do
      Response.error("missing required argument: name")
    else
      with {:ok, kind} <- Validate.node_kind(Map.get(args, :kind, :file)),
           {:ok, opts} <- build_opts(args) do
        case Kerto.Engine.context(engine, kind, name, opts) do
          {:ok, text} -> Response.success(text)
          {:error, :not_found} -> Response.error(not_found_message(engine, kind, name))
        end
      else
        {:error, reason} -> Response.error(reason)
      end
    end
  end

  defp not_found_message(engine, kind, name) do
    case Suggest.similar_names(engine, kind, name) do
      [] -> "not found: #{name} (#{kind})"
      similar -> "not found: #{name} (#{kind}). Similar: #{Enum.join(similar, ", ")}"
    end
  end

  defp build_opts(args) do
    with {:ok, opts} <- maybe_add([], :depth, args, &Validate.integer_val(&1, "depth")),
         {:ok, opts} <- maybe_add(opts, :min_weight, args, &Validate.float_val(&1, "min_weight")) do
      {:ok, opts}
    end
  end

  defp maybe_add(opts, key, args, validator) do
    case Map.get(args, key) do
      nil ->
        {:ok, opts}

      val ->
        case validator.(val) do
          {:ok, coerced} -> {:ok, Keyword.put(opts, key, coerced)}
          {:error, _} = err -> err
        end
    end
  end
end
