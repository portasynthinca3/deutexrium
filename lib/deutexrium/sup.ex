defmodule Deutexrium.Sup do
  @moduledoc """
  Main supervisor
  """

  use Supervisor
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
      Deutexrium.Server.Supervisor,
      Deutexrium.RingStarter,
      Deutexrium.Influx.LoadCntr,
      Deutexrium.Influx
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
