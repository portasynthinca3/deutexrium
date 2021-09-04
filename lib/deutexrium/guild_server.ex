defmodule Deutexrium.GuildServer do
  use GenServer
  require Logger
  alias Deutexrium.Persistence.GuildMeta

  @impl true
  def init(id) do
    # load model and meta
    Logger.info("guild-#{id} server: loading")
    meta = try do
      GuildMeta.load!(id)
    rescue
      _ ->
        Logger.info("guild-#{id} server: creating new meta")
        GuildMeta.dump!(id, %GuildMeta{})
        %GuildMeta{}
    end
    Logger.info("guild-#{id} server: loaded")

    timeout = Application.fetch_env!(:deutexrium, :guild_unload_timeout)
    {:ok, {id, meta, timeout}}
  end

  @impl true
  def handle_call(:get_meta, _from, {_, meta, timeout}=state) do
    {:reply, meta, state, timeout}
  end

  @impl true
  def handle_call({:reset, :settings}, _from, {id, meta, timeout}) do
    Logger.info("guild-#{id} server: settings reset")
    {:reply, :ok, {id, %GuildMeta{}, timeout}, timeout}
  end

  @impl true
  def handle_info(:timeout, {id, meta, _}) do
    # unload everything
    Logger.info("guild-#{id} server: unloading")
    GuildMeta.dump!(id, meta)
    Logger.info("guild-#{id} server: unloaded")

    # exit
    :ets.delete(:guild_servers, id)
    exit(:normal)
  end



  # ===== API =====



  def boot do
    :ets.new(:guild_servers, [:set, :named_table, :public])
    Logger.debug("created guild_servers table")
  end

  def start(id) when is_integer(id) do
    {:ok, pid} = GenServer.start_link(__MODULE__, id)
    :ets.insert(:guild_servers, {id, pid})
    pid
  end

  def maybe_start(id) when is_integer(id) do
    case get_pid(id) do
      :nopid -> start(id)
      pid -> pid
    end
  end

  def get_pid(id) when is_integer(id) do
    case :ets.lookup(:guild_servers, id) do
      [{_, pid}] -> pid
      [] -> :nopid
    end
  end

  def get_meta(id) when is_integer(id) do
    get_pid(id) |> GenServer.call(:get_meta)
  end

  def reset(id, what) when is_integer(id) and is_atom(what) do
    get_pid(id) |> GenServer.call({:reset, what})
  end
end
