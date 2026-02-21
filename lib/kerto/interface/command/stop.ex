defmodule Kerto.Interface.Command.Stop do
  @moduledoc "Stops the kerto daemon via socket shutdown command."

  alias Kerto.Interface.{DaemonClient, Response}

  @socket_path ".kerto/kerto.sock"

  @spec execute(atom(), map()) :: Response.t()
  def execute(_engine, _args) do
    if DaemonClient.daemon_running?(@socket_path) do
      case DaemonClient.send_command(@socket_path, "shutdown") do
        {:ok, %{"ok" => true}} ->
          cleanup()
          Response.success("Daemon stopped")

        {:ok, %{"ok" => false, "error" => err}} ->
          Response.error("shutdown failed: #{err}")

        {:error, :closed} ->
          cleanup()
          Response.success("Daemon stopped")

        {:error, reason} ->
          Response.error("shutdown failed: #{inspect(reason)}")
      end
    else
      Response.error("daemon not running")
    end
  end

  defp cleanup do
    File.rm(".kerto/kerto.pid")
    File.rm(".kerto/kerto.sock")
  end
end
