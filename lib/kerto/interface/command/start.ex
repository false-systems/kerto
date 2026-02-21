defmodule Kerto.Interface.Command.Start do
  @moduledoc "Starts the kerto daemon in the background."

  alias Kerto.Interface.{DaemonClient, Response}

  @socket_path ".kerto/kerto.sock"
  @max_wait_ms 5_000
  @poll_interval_ms 100

  @spec execute(atom(), map()) :: Response.t()
  def execute(_engine, _args) do
    if DaemonClient.daemon_running?(@socket_path) do
      Response.success("Daemon already running")
    else
      case find_escript() do
        {:ok, escript} ->
          launch_daemon(escript)

        :error ->
          Response.error("cannot find kerto executable")
      end
    end
  end

  defp find_escript do
    case System.find_executable("kerto") do
      nil ->
        local = Path.join(File.cwd!(), "kerto")
        if File.exists?(local), do: {:ok, local}, else: :error

      path ->
        {:ok, path}
    end
  end

  defp launch_daemon(escript) do
    File.mkdir_p!(".kerto")
    cmd = "nohup #{escript} --daemon >> .kerto/kerto.log 2>&1 & echo $!"
    {output, 0} = System.cmd("/bin/sh", ["-c", cmd])
    pid_str = String.trim(output)
    File.write!(".kerto/kerto.pid", pid_str)

    if wait_for_socket(@socket_path, @max_wait_ms) do
      Response.success("Daemon started (pid #{pid_str})")
    else
      Response.error("daemon started but socket not ready after #{@max_wait_ms}ms")
    end
  end

  defp wait_for_socket(_path, remaining) when remaining <= 0, do: false

  defp wait_for_socket(path, remaining) do
    if DaemonClient.daemon_running?(path) do
      true
    else
      Process.sleep(@poll_interval_ms)
      wait_for_socket(path, remaining - @poll_interval_ms)
    end
  end
end
