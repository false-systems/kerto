defmodule Kerto.Interface.CLI do
  @moduledoc """
  Escript entry point. Parses args, dispatches command, prints output.

  `main/1` is called by escript — it starts the application, runs the command,
  and exits with 0 (success) or 1 (failure).

  `run/1` is the testable core — no System.halt, no Application.ensure_all_started.
  """

  alias Kerto.Interface.{Dispatcher, Output, Parser}

  @engine :kerto_engine

  @spec main([String.t()]) :: no_return()
  def main(args) do
    Application.ensure_all_started(:kerto)

    case run(args) do
      :ok -> System.halt(0)
      :error -> System.halt(1)
    end
  end

  @spec run([String.t()]) :: :ok | :error
  def run(args) do
    case Parser.parse(args) do
      {:error, reason} ->
        Output.print(Kerto.Interface.Response.error(reason), :text)
        :error

      {command, parsed_args} ->
        format = if parsed_args[:json], do: :json, else: :text
        response = Dispatcher.dispatch(command, @engine, parsed_args)
        Output.print(response, format)
        if response.ok, do: :ok, else: :error
    end
  end
end
