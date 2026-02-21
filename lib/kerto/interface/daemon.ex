defmodule Kerto.Interface.Daemon do
  @moduledoc "Unix domain socket listener for daemon mode."

  use GenServer

  alias Kerto.Interface.{ContextWriter, Dispatcher, Protocol}

  @mutating_commands ~w(learn decide ingest decay weaken delete)

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    socket_path = Keyword.fetch!(opts, :socket_path)
    engine = Keyword.fetch!(opts, :engine)
    context_writer = Keyword.get(opts, :context_writer)

    File.rm(socket_path)
    socket_path |> Path.dirname() |> File.mkdir_p!()

    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :line,
        active: false,
        reuseaddr: true,
        ifaddr: {:local, socket_path}
      ])

    state = %{
      socket_path: socket_path,
      listen_socket: listen_socket,
      engine: engine,
      context_writer: context_writer
    }

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, state) do
    spawn_acceptor(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:spawn_acceptor, state) do
    spawn_acceptor(state)
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :gen_tcp.close(state.listen_socket)
    File.rm(state.socket_path)
    :ok
  end

  defp spawn_acceptor(state) do
    parent = self()
    listen = state.listen_socket
    engine = state.engine
    context_writer = state.context_writer

    spawn_link(fn ->
      case :gen_tcp.accept(listen) do
        {:ok, client} ->
          send(parent, :spawn_acceptor)
          handle_client(client, engine, context_writer)

        {:error, _} ->
          :ok
      end
    end)
  end

  defp handle_client(client, engine, context_writer) do
    case :gen_tcp.recv(client, 0, 5_000) do
      {:ok, line} ->
        response = dispatch_line(line, engine, context_writer)
        :gen_tcp.send(client, response <> "\n")

      {:error, _} ->
        :ok
    end

    :gen_tcp.close(client)
  end

  defp dispatch_line(line, engine, context_writer) do
    case Protocol.decode_request(line) do
      {:error, reason} ->
        Protocol.encode_response(Kerto.Interface.Response.error(reason))

      {"shutdown", _args} ->
        response = Protocol.encode_response(Kerto.Interface.Response.success(:ok))

        spawn(fn ->
          Process.sleep(100)
          System.stop(0)
        end)

        response

      {command, args} ->
        response = Dispatcher.dispatch(command, engine, args)

        if context_writer && command in @mutating_commands do
          ContextWriter.notify_mutation(context_writer)
        end

        Protocol.encode_response(response)
    end
  end
end
