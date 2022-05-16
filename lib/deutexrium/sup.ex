defmodule Deutexrium.Sup do
  use Supervisor
  @moduledoc "Main supervisor"

  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop do
    Supervisor.stop(__MODULE__)
    Logger.notice("supervisor stopped")
  end

  @impl true
  def init(_init_arg) do
    children = [
      Deutexrium,
      Deutexrium.Influx.LoadCntr,
      Deutexrium.Influx,
      Deutexrium.Influx.Logger,
      {Registry, keys: :unique, name: Registry.Server},
      Deutexrium.Presence
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
