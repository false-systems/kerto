defmodule Kerto.MixProject do
  use Mix.Project

  def project do
    [
      app: :kerto,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Kerto.Interface.CLI],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
