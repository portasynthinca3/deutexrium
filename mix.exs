defmodule Deutexrium.MixProject do
  use Mix.Project

  def project do
    [
      app: :deutexrium,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Deutexrium.App, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gun, github: "ninenines/gun", override: true}, # specific version required by nostrum
      {:nostrum, github: "kraigie/nostrum", ref: "1776edbfd7a6e168e71beaa486abc3b3de71d4d2"},
      {:logger_file_backend, "~> 0.0"},
      {:markov, "~> 1.1"},
      {:ex_hash_ring, "~> 6.0"},
      {:graceful_stop, "~> 0.2.0"},
      {:timex, "~> 3.0"},
      {:veritaserum, "~> 0.2.2"},
      {:jason, "~> 1.2"}
    ]
  end
end
