defmodule Deutexrium.Server.Supervisor do
  @moduledoc """
  Supervises request routers
  """

  use DynamicSupervisor
  require Logger
  alias ExHashRing.Ring

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.debug("router supervisor started")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ==== API ====

  @spec router_cnt() :: integer()
  def router_cnt do
    %{workers: cnt} = DynamicSupervisor.count_children(__MODULE__)
    cnt
  end

  @spec add_routers(integer()) :: [pid()]
  def add_routers(number) do
    Logger.debug("adding #{number} request routers")
    for _ <- 1..number do
      {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, Deutexrium.Server.RqRouter)

      [ring: ring] = :ets.lookup(:ring_state, :ring)
      {:ok, _} = Ring.add_node(ring, pid)
      pid
    end
  end

  @spec aggregate(%{any => any}, fun(pid(), %{any => any})) :: %{any => any}
  defp aggregate(start, fun) do
    children = DynamicSupervisor.which_children(__MODULE__)
    values = for {_, pid, :worker, _} <- children do
      pid |> fun.()
    end
    # sum values
    values |> Enum.reduce(start, &ListUtil.sum_maps/2)
  end

  @spec server_count() :: %{guilds: integer(), channels: integer()}
  def server_count do
    aggregate(%{channels: 0, guilds: 0}, &Deutexrium.Server.RqRouter.server_count/1)
  end

  @spec shutdown() :: [:ok]
  def shutdown do
    children = DynamicSupervisor.which_children(__MODULE__)
    for {_, pid, :worker, _} <- children do
      pid |> Deutexrium.Server.RqRouter.shutdown
    end
  end
end
