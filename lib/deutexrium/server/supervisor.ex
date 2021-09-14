defmodule Deutexrium.Server.Supervisor do
  use DynamicSupervisor
  require Logger
  alias ExHashRing.Ring

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def add_routers(number) do
    Logger.debug("adding #{number} request routers")
    for _ <- 1..number do
      {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, Deutexrium.Server.RqRouter)

      [ring: ring] = :ets.lookup(:ring_state, :ring)
      {:ok, _} = Ring.add_node(ring, pid)
    end
  end

  @impl true
  def init(_) do
    Logger.debug("router supervisor started")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
