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
      nostrum: "~> 0.4"
    ]
  end
end
