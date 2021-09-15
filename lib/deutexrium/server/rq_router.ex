defmodule Deutexrium.Server.RqRouter do
  use GenServer
  require Logger
  alias ExHashRing.Ring
  alias Deutexrium.Server

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  defp try_calling(map, {type, id}=target, rq) do
    module = case type do
      :guild -> Server.Guild
      :channel -> Server.Channel
    end

    case map |> Map.get(id) do
      nil ->
        Logger.debug("starting server for target #{inspect target}")
        {:ok, pid} = GenServer.start(module, id)
        map = map |> Map.put(id, pid)
        try_calling(map, target, rq)

      pid when is_pid(pid) ->
        try do
          result = GenServer.call(pid, rq, 4500)
          {map, result}
        catch
          :exit, _ ->
            Logger.warn("restarting server for target #{inspect target}")
            # kill it just in case
            Process.exit(pid, :normal)
            try_calling(map |> Map.delete(id), target, rq)
        end
    end
  end

  defp router_pid(target) do
    [ring: ring] = :ets.lookup(:ring_state, :ring)
    {:ok, pid} = ring |> Ring.find_node(inspect target)

    Logger.debug("chose router #{pid} for target #{inspect target}")
    pid
  end


  @impl true
  def init(_) do
    {:ok, {%{}, %{}}}
  end

  @impl true
  def handle_call({:route, {:guild, _}=target, rq}, _from, {%{}=guild_map, chan_map}) do
    {guild_map, result} = try_calling(guild_map, target, rq)
    {:reply, result, {guild_map, chan_map}}
  end

  @impl true
  def handle_call({:route, {:channel, _}=target, rq}, _from, {guild_map, %{}=chan_map}) do
    {chan_map, result} = try_calling(chan_map, target, rq)
    {:reply, result, {guild_map, chan_map}}
  end

  @impl true
  def handle_call(:server_count, _from, {%{}=guild_map, %{}=chan_map}=state) do
    {:reply, %{
      guilds: map_size(guild_map),
      channels: map_size(chan_map)
    }, state}
  end

  # ==== API =====

  @spec route({:channel|:guild, integer() | {integer(), integer()}}, any()) :: any()
  def route({type, _}=target, rq) when type == :channel or type == :guild do
    router_pid(target) |> GenServer.call({:route, target, rq}, 10000)
  end

  @spec route_to_guild(integer(), any()) :: any()
  def route_to_guild(id, rq) when is_integer(id) do
    route({:guild, id}, rq)
  end

  @spec route_to_chan({integer(), integer()}, any()) :: any()
  def route_to_chan({cid, gid}=id, rq) when is_integer(cid) and is_integer(gid) do
    route({:channel, id}, rq)
  end

  @spec server_count(pid()) :: %{guilds: integer(), channels: integer()}
  def server_count(pid) do
    pid |> GenServer.call(:server_count)
  end
end
