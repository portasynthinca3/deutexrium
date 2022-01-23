defmodule Deutexrium.MixProject do
  use Mix.Project

  def project do
    [
      app: :deutexrium,
      version: "0.3.3",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Deutexrium.App, []},
      extra_applications: [:logger, :os_mon]
    ]
  end

  defp deps do
    [
      # {:gun, github: "ninenines/gun", override: true}, # specific version required by nostrum
      {:nostrum, github: "kraigie/nostrum", ref: "master"},
      # {:nostrum, "~> 0.5.0-rc1"},
      {:logger_file_backend, "~> 0.0.13"},
      {:cyanide, "~> 1.0"},
      {:markov, "~> 1.2.1"},
      {:ex_hash_ring, "~> 6.0"},
      {:graceful_stop, "~> 0.2.0"},
      {:timex, "~> 3.0"},
      {:veritaserum, "~> 0.2.2"},
      {:jason, "~> 1.3"},
      {:instream, "~> 1.0"},
      {:observer_cli, "~> 1.7"}
    ]
  end
end
