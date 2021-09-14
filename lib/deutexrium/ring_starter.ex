defmodule Deutexrium.RingStarter do
  use GenServer
  require Logger
  alias ExHashRing.Ring

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  @impl true
  def init(_) do
    :ets.new(:ring_state, [:named_table, :set])
    {:ok, pid} = Ring.start_link()
    :ets.insert(:ring_state, {:ring, pid})
    Logger.debug("ring started")

    Application.fetch_env!(:deutexrium, :default_router_cnt)
        |> Deutexrium.Server.Supervisor.add_routers

    {:ok, {}}
  end

  @impl true
  def handle_call(_, _, state) do
    {:noreply, state}
  end
end
