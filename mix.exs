defmodule Deutexrium.MixProject do
  use Mix.Project

  def project do
    [
      app: :deutexrium,
      version: "2.0.4",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        deutexrium: [
          cookie: "deutexrium"
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Deutexrium.App, []},
      extra_applications: [:logger, :os_mon, :gun, :tools, :mnesia, :observer]
    ]
  end

  defp deps do
    [
      {:gun, "~> 2.0", hex: :remedy_gun},
      # {:nostrum, github: "kraigie/nostrum", ref: "master"},
      {:nostrum, "~> 0.6.1"},
      {:logger_file_backend, "~> 0.0.13"},
      {:cyanide, "~> 1.0"},
      {:markov, "~> 4.1.3"},
      {:timex, "~> 3.0"},
      {:jason, "~> 1.3"},
      {:instream, "~> 1.0"},
      {:observer_cli, "~> 1.7"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:flow, "~> 1.2"}
    ]
  end
end
