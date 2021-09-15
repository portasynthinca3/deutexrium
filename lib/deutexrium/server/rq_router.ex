defmodule Deutexrium.Server.RqRouter do
  use GenServer
  require Logger
  alias ExHashRing.Ring
  alias Deutexrium.Server
  alias Deutexrium.Server.RqRouter.State

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  defp forward_request(map, {type, id}=target, rq) do
    module = case type do
      :guild -> Server.Guild
      :channel -> Server.Channel
    end

    case map |> Map.get(id) do
      nil ->
        Logger.debug("router-#{inspect self()}: starting server for target #{inspect target}")
        {:ok, pid} = GenServer.start(module, id)
        map = map |> Map.put(id, pid)
        forward_request(map, target, rq)

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          ref = make_ref()
          Logger.debug("router-#{inspect self()}: forwarding request to #{inspect target}")
          pid |> send({:"$gen_call", {self(), ref}, rq})
          {map, ref}
        else
          Logger.debug("router-#{inspect self()}: server for target #{inspect target} died")
          # kill it just in case
          Process.exit(pid, :normal)
          forward_request(map |> Map.delete(id), target, rq)
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
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:route, {:guild, _}=target, rq}, from, %State{}=state) when not state.shut_down do
    {guild_pids, ref} = forward_request(state.guild_pids, target, rq)
    {:noreply, %{state |
      guild_pids: guild_pids,
      ref_receivers: state.ref_receivers |> Map.put(ref, from)
    }}
  end

  @impl true
  def handle_call({:route, {:channel, _}=target, rq}, from, %State{}=state) when not state.shut_down do
    {channel_pids, ref} = forward_request(state.channel_pids, target, rq)
    {:noreply, %{state |
      channel_pids: channel_pids,
      ref_receivers: state.ref_receivers |> Map.put(ref, from)
    }}
  end

  @impl true
  def handle_call(:server_count, _from, %State{}=state) do
    {:reply, %{
      guilds: map_size(state.guild_pids),
      channels: map_size(state.channel_pids)
    }, state}
  end

  @impl true
  def handle_call(:shutdown, _from, %State{}=state) do
    for {_, pid} <- Map.merge(state.guild_pids, state.channel_pids) do
      pid |> GenServer.cast({:shutdown, false})
    end
    {:reply, :ok, %{state | shut_down: true}}
  end

  @impl true
  def handle_call({:force_restart, {type, id}=target}, _from, %State{}=state) when not state.shut_down do
    Logger.warn("router-#{inspect self()}: force-restarting #{inspect target}")
    state_field = case type do
      :guild -> :guild_pids
      :channel -> :channel_pids
    end
    map = state |> Map.get(state_field)
    case map |> Map.get(id) do
      nil ->
        {:reply, :noserver, state}
      oldpid ->
        Process.exit(oldpid, :normal)
        {:reply, :ok, %{state |
          state_field => map |> Map.delete(target)
        }}
    end
  end

  def handle_call(term, _, state) do
    Logger.warn("invalid router request: #{inspect term}")
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, response}, %State{}=state) when is_reference(ref) do
    %{^ref => {receiver, response_ref}} = state.ref_receivers
    Logger.debug("router-#{inspect self()}: forwarding response to #{receiver}")
    send(receiver, {response_ref, response})
    {:noreply, %{state |
      ref_receivers: state.ref_receivers |> Map.delete(ref)
    }}
  end

  # ==== API =====

  @spec route({:channel|:guild, integer() | {integer(), integer()}}, any()) :: any()
  def route({type, _}=target, rq) when type == :channel or type == :guild do
    router_pid(target) |> GenServer.call({:route, target, rq})
  end

  @spec route_to_guild(:channel|:guild, any()) :: any()
  def route_to_guild(id, rq) when is_integer(id) do
    route({:guild, id}, rq)
  end

  @spec route_to_chan({:channel|:guild, integer()}, any()) :: any()
  def route_to_chan({cid, gid}=id, rq) when is_integer(cid) and is_integer(gid) do
    route({:channel, id}, rq)
  end

  @spec server_count(pid()) :: %{guilds: integer(), channels: integer()}
  def server_count(pid) do
    pid |> GenServer.call(:server_count)
  end

  @spec shutdown(pid()) :: :ok
  def shutdown(pid) do
    pid |> GenServer.call(:shutdown)
  end

  @spec force_restart(pid(), {:channel|:guild, integer()}) :: :ok | :noserver
  def force_restart(pid, {type, _}=target) when is_pid(pid) and (type == :channel or type == :guild) do
    pid |> GenServer.call({:force_restart, target})
  end
end
