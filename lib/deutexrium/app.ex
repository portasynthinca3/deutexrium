defmodule Deutexrium.App do
  use Application
  @moduledoc """
  Deutexrium OTP app
  """

  @impl true
  def start(_type, _args) do
    dir = Application.fetch_env!(:deutexrium, :data_path)
    File.mkdir_p(dir |> Path.join("data"))

    scrape_port = Application.fetch_env!(:deutexrium, :scrape_port)
    Supervisor.start_link([
      {Registry, keys: :unique, name: Registry.Server},
      {DynamicSupervisor, name: Deutexrium.ServerSup},
      {Plug.Cowboy, scheme: :http, plug: Deutexrium.Plug, options: [port: scrape_port]},
      Deutexrium.Prometheus,
      Deutexrium.Translation,
      Deutexrium.Persistence,
      Deutexrium.CommandHolder,
      Deutexrium.Command,
      Deutexrium.Presence,
    ], strategy: :one_for_one, name: Deutexrium.RootSupervisor)
  end
end
