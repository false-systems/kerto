defmodule Kerto.Interface.DaemonClient do
  @moduledoc "Thin client for communicating with the daemon over Unix socket."

  @spec send_command(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_command(socket_path, command, args \\ %{}) do
    payload = Jason.encode!(%{command: command, args: args}) <> "\n"

    with {:ok, socket} <- connect(socket_path),
         :ok <- :gen_tcp.send(socket, payload),
         {:ok, line} <- :gen_tcp.recv(socket, 0, 5_000) do
      :gen_tcp.close(socket)
      {:ok, Jason.decode!(line)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec daemon_running?(String.t()) :: boolean()
  def daemon_running?(socket_path) do
    case connect(socket_path) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp connect(socket_path) do
    :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: false], 1_000)
  end
end
