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
      {:nostrum, github: "kraigie/nostrum", ref: "7f036c452f7c7c8422e8d86768217e606ef32255"},
      {:logger_file_backend, "~> 0.0"},
      {:markov, "~> 0.1"}
    ]
  end
end
