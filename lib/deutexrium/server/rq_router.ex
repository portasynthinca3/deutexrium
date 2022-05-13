defmodule Deutexrium.Server.RqRouter do
  @moduledoc "Routes requests and responses between handling servers and Nostrum event handlers"

  use GenServer
  require Logger
  alias ExHashRing.Ring
  alias Deutexrium.Server

  defmodule State do
    @moduledoc "Request router state"
    defstruct pids: %{channel: %{}, voice: %{}, guild: %{}, settings: %{}},
              ref_receivers: %{},
              shut_down: false
  end

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  defp forward_request(map, {type, id} = target, rq) do
    module = case type do
      :guild -> Server.Guild
      :channel -> Server.Channel
      :voice -> Server.Voice
      :settings -> Server.Settings
    end

    case map |> Map.get(id) do
      # the corresponding server was never started
      # start it and retry
      nil ->
        {:ok, pid} = GenServer.start(module, id)
        map = map |> Map.put(id, pid)
        forward_request(map, target, rq)

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          # the server is up
          ref = make_ref()
          pid |> send({:"$gen_call", {self(), ref}, rq})
          # delete the ref in 10 secs
          # it should get deleted after the server sent a response, but that won't
          # happen if it crashes while handling the request
          Process.send_after(self(), {:delete, ref}, 20_000)
          {map, ref}
        else
          # the server was started at some point but it has crashed
          # kill it just in case
          Process.exit(pid, :normal)
          forward_request(map |> Map.delete(id), target, rq)
        end
    end
  end

  defp router_pid(target) do
    [ring: ring] = :ets.lookup(:ring_state, :ring)
    {:ok, pid} = ring |> Ring.find_node(inspect(target))
    pid
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 10_000)
  end


  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:route, {t_type, _} = target, rq}, from, %State{} = state) when not state.shut_down do
    %{^t_type => map} = state.pids
    {new_map, ref} = forward_request(map, target, rq)
    {:noreply, %{state |
      pids: %{
        state.pids |
        t_type => new_map
      },
      ref_receivers: state.ref_receivers |> Map.put(ref, from)
    }}
  end

  def handle_call(:server_count, _from, %State{} = state) do
    {:reply, state.pids |> Map.map(fn {_, v} -> map_size(v) end), state}
  end

  def handle_call(:shutdown, _from, %State{} = state) do
    for {_, pid} <- Enum.concat(state.pids |> Map.values) do
      pid |> GenServer.cast({:shutdown, false})
    end
    {:reply, :ok, %{state | shut_down: true}}
  end

  @impl true
  def handle_call({:force_restart, {type, id} = target}, _from, %State{} = state) when not state.shut_down do
    Logger.warn("router-#{inspect self()}: force-restarting #{inspect target}")
    %{^type => map} = state.pids
    case map |> Map.get(id) do
      nil ->
        {:reply, :noserver, state}
      oldpid ->
        Process.exit(oldpid, :normal)
        {:reply, :ok, %{state | pids: %{
          state.pids | type => map |> Map.delete(target)
        }}}
    end
  end

  @impl true
  def handle_call(term, _, state) do
    Logger.warn("invalid router request: #{inspect term}")
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, response}, %State{} = state) when is_reference(ref) do
    case state.ref_receivers |> Map.get(ref) do
      nil ->
        Logger.warn("router-#{inspect self()}: no receiver for ref #{inspect ref}")
        {:noreply, state}

      {receiver, response_ref} ->
        send(receiver, {response_ref, response})
        {:noreply, %{state |
          ref_receivers: state.ref_receivers |> Map.delete(ref)
        }}
    end
  end

  @impl true
  def handle_info({:delete, ref}, %State{} = state) when is_reference(ref) do
    {:noreply, %{state |
      ref_receivers: state.ref_receivers |> Map.delete(ref)
    }}
  end

  @impl true
  def handle_info(:cleanup, %State{} = state) do
    Logger.debug("router-#{inspect self()}: cleaning up")
    schedule_cleanup()
    {:noreply, %{state |
      pids: state.pids |> Map.map(fn {_, map} ->
        Map.filter(map, fn {_, v} -> Process.alive?(v) end)
      end)
    }}
  end

  # ==== API =====

  @type server_type() :: :channel | :guild | :voice | :settings

  @spec route({server_type(), integer() | {integer(), integer()}}, any()) :: any()
  def route({type, _} = target, rq) when type == :channel or type == :guild or type == :voice or type == :settings do
    # increased timeout for CHONKERS (like the global model, it almost has half a million msgs!)
    router_pid(target) |> GenServer.call({:route, target, rq}, 15_000)
  end

  @spec route_to_guild(integer(), any()) :: any()
  def route_to_guild(id, rq) when is_integer(id) do
    route({:guild, id}, rq)
  end

  @spec route_to_chan({integer(), integer()}, any()) :: any()
  def route_to_chan({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid) do
    route({:channel, id}, rq)
  end

  @spec route_to_voice({integer(), integer()}, any()) :: any()
  def route_to_voice({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid) do
    route({:voice, id}, rq)
  end

  @spec route_to_settings({integer(), integer()}, any()) :: any()
  def route_to_settings({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid) do
    route({:settings, id}, rq)
  end

  @spec server_count(pid()) :: %{guilds: integer(), channels: integer(), voice: integer(), settings: integer()}
  def server_count(pid) do
    pid |> GenServer.call(:server_count)
  end

  @spec shutdown(pid()) :: :ok
  def shutdown(pid) do
    pid |> GenServer.call(:shutdown)
  end

  @spec force_restart(pid(), {server_type(), integer()}) :: :ok | :noserver
  def force_restart(pid, {type, _} = target) when is_pid(pid) and (type == :channel or type == :guild) do
    pid |> GenServer.call({:force_restart, target})
  end
end
