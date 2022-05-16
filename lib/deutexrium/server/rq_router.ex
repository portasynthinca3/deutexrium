defmodule Deutexrium.Server.RqRouter do
  @moduledoc "Resource server supervisor and router for requests"

  require Logger
  alias Deutexrium.Server

  @type server_type :: :channel | :guild | :voice | :settings
  @type target :: {:channel, {integer, integer}} | {:guild, integer} | {:voice, {integer, integer}} | {:settings, {integer, integer}}
  defguard is_server_type(term) when term == :channel or term == :guild or term == :voice or term == :settings

  @spec ensure(target) :: {:via, Registry, {Registry.Server, target}}
  @doc "Ensures that a server is started"
  def ensure({type, id} = what) do
    name = {:via, Registry, {Registry.Server, what}}

      # get server module
      module = case type do
        :channel -> Server.Channel
        :guild -> Server.Guild
        :voice -> Server.Voice
        :settings -> Server.Settings
      end

      # start it (returns an error if already srarted, which is okay)
      GenServer.start(module, id, name: name)
      name
  end

  @spec route({server_type, integer | {integer, integer}}, any) :: any
  def route({type, _id} = what, rq) when is_server_type(type) do
    # big timeout for slow servers
    ensure(what) |> GenServer.call(rq, 15_000)
  end

  @spec route_to_guild(integer, any) :: any
  def route_to_guild(id, rq) when is_integer(id), do: route({:guild, id}, rq)

  @spec route_to_chan({integer, integer}, any) :: any
  def route_to_chan({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid), do: route({:channel, id}, rq)

  @spec route_to_voice({integer, integer}, any) :: any
  def route_to_voice({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid), do: route({:voice, id}, rq)

  @spec route_to_settings({integer, integer}, any) :: any
  def route_to_settings({cid, gid} = id, rq) when is_integer(cid) and is_integer(gid), do: route({:settings, id}, rq)

  @spec server_count(pid()) :: %{guilds: integer, channels: integer, voice: integer, settings: integer}
  def server_count(pid) do
    pid |> GenServer.call(:server_count)
  end

  @spec server_count :: %{guild: non_neg_integer, channel: non_neg_integer, voice: non_neg_integer, settings: non_neg_integer}
  def server_count do
    [:guild, :channel, :voice, :settings] |> Enum.map(fn type ->
                                              # I HATE MATCH SPECIFICATIONS
      {type, Registry.select(Registry.Server, [{{{type, :"$1"}, :_, :_}, [], [:"$1"]}]) |> length} end)
      |> Enum.into(%{})
  end

  @spec shutdown :: [:ok]
  def shutdown do
    Registry.select(Registry.Server, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.map(& &1 |> ensure |> GenServer.cast({:shutdown, true}))
  end
end
