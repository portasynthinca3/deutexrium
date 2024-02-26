defmodule Deutexrium.MixProject do
  use Mix.Project

  def project do
    [
      app: :deutexrium,
      version: "2.6.1",
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
      extra_applications: [
        :logger,
        :os_mon,
        :gun,
        :tools,
        :recon,
        :sasl,
        :prometheus_ex
      ]
    ]
  end

  defp deps do
    [
      {:nostrum, github: "kraigie/nostrum", ref: "d2daf4941927bc4452a4e79acbef4a574ce32f57"},
      {:logger_file_backend, "~> 0.0.13"},
      {:cyanide, "~> 1.0"},
      {:markov, "~> 4.1.3"},
      {:timex, "~> 3.0"},
      {:jason, "~> 1.3"},
      {:prometheus_ex, "~> 3.0.5", github: "lanodan/prometheus.ex", ref: "31f7fb", override: true}, # fork that supports elixir 1.14
      {:prometheus_plugs, "~> 1.1"},
      {:plug_cowboy, "~> 2.0"},
      {:cowlib, "~> 2.12", override: true},
      {:observer_cli, "~> 1.7"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:flow, "~> 1.2"},
      {:recon, "~> 2.5"},
      {:exla, "~> 0.4.2", override: true},
      {:floki, "~> 0.34.0"}
    ]
  end
end
