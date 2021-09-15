defmodule Deutexrium.Server.Guild do
  use GenServer
  require Logger
  alias Deutexrium.Persistence.GuildMeta
  alias Deutexrium.Server.RqRouter

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
  def handle_call({:reset, :settings}, _from, {id, _, timeout}) do
    Logger.info("guild-#{id} server: settings reset")
    {:reply, :ok, {id, %GuildMeta{}, timeout}, timeout}
  end

  @impl true
  def handle_call({:set, setting, val}, _from, {id, meta, timeout}) do
    {:reply, :ok, {id, Map.put(meta, setting, val), timeout}, timeout}
  end

  @impl true
  def handle_call({:scoreboard, author}, _from, {id, meta, timeout}) do
    {:reply, :ok, {id, %{meta | user_stats: Map.put(meta.user_stats, author, (Map.get(meta.user_stats, author) || 0) + 1)}, timeout}, timeout}
  end

  @impl true
  def handle_cast({:shutdown, freeze}, {id, _, _}=state) do
    handle_shutdown(state, not freeze)
    if freeze do
      Logger.notice("guild-#{id} server: freezing")
      infinite_loop()
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    handle_shutdown(state, true)
  end

  defp handle_shutdown({id, meta, _}=_state, do_exit) do
    # unload everything
    Logger.info("guild-#{id} server: unloading")
    GuildMeta.dump!(id, meta)
    Logger.info("guild-#{id} server: unloaded")

    # exit
    if do_exit do
      exit(:normal)
    end
  end

  defp infinite_loop do
    infinite_loop()
  end



  # ===== API =====





  @spec get_meta(integer()) :: %GuildMeta{}
  def get_meta(id) when is_integer(id) do
    id |> RqRouter.route_to_guild(:get_meta)
  end

  @spec reset(integer(), atom()) :: :ok
  def reset(id, what) when is_integer(id) and is_atom(what) do
    id |> RqRouter.route_to_guild({:reset, what})
  end

  @spec scoreboard_add_one(integer(), integer()) :: :ok
  def scoreboard_add_one(id, author) when is_integer(id) and is_integer(author) do
    id |> RqRouter.route_to_guild({:scoreboard, author})
  end

  @spec set(integer(), atom(), any()) :: :ok
  def set(id, setting, value) when is_integer(id) and is_atom(setting) do
    id |> RqRouter.route_to_guild({:set, setting, value})
  end
end