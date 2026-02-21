defmodule Kerto.Interface.CLI do
  @moduledoc "Escript entry point with mode switching: MCP, daemon, socket, or direct."

  alias Kerto.Interface.{DaemonClient, Dispatcher, Help, MCP, Output, Parser}

  @engine :kerto_engine
  @socket_path ".kerto/kerto.sock"
  @direct_commands ~w(init start stop)

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case args do
      ["mcp" | _] ->
        Application.ensure_all_started(:kerto)
        MCP.run(@engine)

      ["--daemon" | _] ->
        Application.ensure_all_started(:kerto)
        run_daemon()

      _ ->
        Application.ensure_all_started(:kerto)

        case run(args) do
          :ok -> System.halt(0)
          :error -> System.halt(1)
        end
    end
  end

  @spec run([String.t()]) :: :ok | :error
  def run(["--help" | _]), do: help(nil)
  def run(["-h" | _]), do: help(nil)
  def run([cmd, "--help" | _]), do: help(cmd)
  def run([cmd, "-h" | _]), do: help(cmd)

  def run(args) do
    case Parser.parse(args) do
      {:error, reason} ->
        Output.print(Kerto.Interface.Response.error(reason), :text)
        :error

      {command, parsed_args} ->
        format = if parsed_args[:json], do: :json, else: :text

        if command in @direct_commands do
          dispatch_local(command, parsed_args, format)
        else
          dispatch_maybe_socket(command, parsed_args, format)
        end
    end
  end

  defp dispatch_local(command, args, format) do
    response = Dispatcher.dispatch(command, @engine, args)
    Output.print(response, format)
    if response.ok, do: :ok, else: :error
  end

  defp dispatch_maybe_socket(command, args, format) do
    if DaemonClient.daemon_running?(@socket_path) do
      dispatch_socket(command, args, format)
    else
      dispatch_local(command, args, format)
    end
  end

  defp dispatch_socket(command, args, format) do
    clean_args = Map.drop(args, [:json])

    case DaemonClient.send_command(@socket_path, command, stringify_args(clean_args)) do
      {:ok, %{"ok" => true, "data" => data}} ->
        Output.print(Kerto.Interface.Response.success(data), format)
        :ok

      {:ok, %{"ok" => false, "error" => error}} ->
        Output.print(Kerto.Interface.Response.error(error), format)
        :error

      {:error, reason} ->
        Output.print(Kerto.Interface.Response.error("socket error: #{inspect(reason)}"), format)
        :error
    end
  end

  defp stringify_args(args) do
    Map.new(args, fn
      {k, v} when is_atom(v) -> {Atom.to_string(k), Atom.to_string(v)}
      {k, v} -> {Atom.to_string(k), v}
    end)
  end

  defp run_daemon do
    socket_path = @socket_path
    File.mkdir_p!(Path.dirname(socket_path))

    {:ok, _} =
      Kerto.Interface.ContextWriter.start_link(
        engine: @engine,
        path: ".kerto/CONTEXT.md",
        name: Kerto.Interface.ContextWriter
      )

    {:ok, _} =
      Kerto.Interface.Daemon.start_link(
        socket_path: socket_path,
        engine: @engine,
        context_writer: Kerto.Interface.ContextWriter,
        name: Kerto.Interface.Daemon
      )

    Process.sleep(:infinity)
  end

  defp help(command) do
    IO.puts(Help.render(command))
    :ok
  end
end
