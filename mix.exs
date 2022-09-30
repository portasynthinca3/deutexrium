defmodule Deutexrium.MixProject do
  use Mix.Project

  def project do
    [
      app: :deutexrium,
      version: "1.4.2",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Deutexrium.App, []},
      extra_applications: [:logger, :os_mon, :gun, :tools]
    ]
  end

  defp deps do
    [
      {:gun, "~> 2.0", hex: :remedy_gun},
      {:nostrum, github: "kraigie/nostrum", ref: "master"},
      # {:nostrum, "~> 0.5.1"},
      {:logger_file_backend, "~> 0.0.13"},
      {:cyanide, "~> 1.0"},
      {:markov, "~> 1.3"},
      {:graceful_stop, "~> 0.2.0"},
      {:timex, "~> 3.0"},
      {:veritaserum, "~> 0.2.2"},
      {:jason, "~> 1.3"},
      {:instream, "~> 1.0"},
      {:observer_cli, "~> 1.7"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end
end
