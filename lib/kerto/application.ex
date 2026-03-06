defmodule Kerto.Application do
  @moduledoc """
  OTP Application supervisor.

  Starts the Engine under supervision with the default `:kerto_engine` name.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    persistence_path = System.get_env("KERTO_PATH", ".kerto")
    plugins = load_plugins(persistence_path)

    children = [
      {Kerto.Engine, name: :kerto_engine, persistence_path: persistence_path, plugins: plugins}
    ]

    opts = [strategy: :one_for_one, name: Kerto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec load_plugins(String.t()) :: [module()]
  def load_plugins(persistence_path) do
    path = Path.join(persistence_path, "plugins.exs")

    case File.read(path) do
      {:ok, content} ->
        {result, _bindings} = Code.eval_string(content)
        validate_plugins(result)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Failed to read #{path}: #{reason}")
        []
    end
  rescue
    e ->
      Logger.warning("Failed to evaluate plugins.exs: #{Exception.message(e)}")
      []
  end

  defp validate_plugins(plugins) when is_list(plugins) do
    Enum.each(plugins, fn
      mod when is_atom(mod) -> :ok
      other -> raise "Invalid plugin entry: #{inspect(other)}, expected a module atom"
    end)

    plugins
  end

  defp validate_plugins(other) do
    raise "plugins.exs must return a list, got: #{inspect(other)}"
  end
end
