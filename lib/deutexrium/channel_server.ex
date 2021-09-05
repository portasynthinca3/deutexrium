defmodule Deutexrium.ChannelServer do
  use GenServer
  require Logger
  alias Deutexrium.Persistence.{Meta, Model}
  alias Deutexrium.GuildServer

  defp get_setting({{_, guild}, meta}, setting) do
    if Map.get(meta, setting) == nil do
      GuildServer.get_meta(guild) |> Map.get(setting)
    else
      Map.get(meta, setting)
    end
  end

  @impl true
  def init({id, guild}) do
    # load model and meta
    Logger.info("channel-#{id} server: loading")
    {meta, model} = try do
      {Meta.load!(id), Model.load!(id)}
    rescue
      _ ->
        Logger.info("channel-#{id} server: creating new model and meta")
        Meta.dump!(id, %Meta{})
        Model.dump!(id, %Model{})
        {%Meta{}, %Model{}}
    end
    Logger.info("channel-#{id} server: loaded")

    timeout = Application.fetch_env!(:deutexrium, :channel_unload_timeout)
    {:ok, {{id, guild}, meta, model, timeout}, timeout}
  end

  @impl true
  def handle_call(:get_meta, _from, {_, meta, _, timeout}=state) do
    {:reply, meta, state, timeout}
  end
  @impl true
  def handle_call(:get_model, _from, {_, _, model, timeout}=state) do
    {:reply, Map.delete(model, :data), state, timeout}
  end

  @impl true
  def handle_call({:message, message, by_bot, author_id}, _from, {{_, guild}=id, meta, model, timeout}=state) do
    # don't train if ignoring bots
    unless by_bot and get_setting({id, meta}, :ignore_bots) do
      # check training settings
      train = id == 0 or get_setting({id, meta}, :train)
      global_train = id != 0 and get_setting({id, meta}, :global_train)

      # train local model
      model = if train do
        %{model | data: Markov.train(model.data, message),
          trained_on: model.trained_on + 1}
      else model
      end

      # train global model
      model = if global_train do
        handle_message(0, message, false, 0)
        %{model | global_trained_on: model.global_trained_on + 1}
      else model
      end

      # auto-generation
      autorate = get_setting({id, meta}, :autogen_rate)
      {reply, meta} = cond do
        (autorate > 0) and (meta.total_msgs >= meta.next_gen_milestone) ->
          reply = {:message, Markov.generate_text(model.data)}
          # set new milestone
          {reply, %{meta | next_gen_milestone: meta.next_gen_milestone +
              autorate +
              :rand.uniform(autorate) - div(autorate, 2)}}

        true -> {:ok, meta}
      end

      # scoreboard
      GuildServer.scoreboard_add_one(guild, author_id)

      {:reply, reply,
        {id, %{meta | total_msgs: meta.total_msgs + 1}, model, timeout}, timeout}
    else
      {:reply, :ok, state, timeout}
    end
  end

  @impl true
  def handle_call(:generate, _from, {_, _, model, timeout}=state) do
    {:reply, Markov.generate_text(model.data), state, timeout}
  end

  @impl true
  def handle_call({:reset, :settings}, _from, {{cid, _}=id, _, model, timeout}) do
    Logger.info("channel-#{cid} server: settings reset")
    {:reply, :ok, {id, %Meta{}, model, timeout}, timeout}
  end
  @impl true
  def handle_call({:reset, :model}, _from, {{cid, _}=id, meta, _, timeout}) do
    Logger.info("channel-#{cid} server: model reset")
    {:reply, :ok, {id, meta, %Model{}, timeout}, timeout}
  end

  @impl true
  def handle_call({:set, setting, val}, _from, {id, meta, model, timeout}) do
    {:reply, :ok, {id, Map.put(meta, setting, val), model, timeout}, timeout}
  end

  @impl true
  def handle_call(:timeout, _from, state) do
    handle_shutdown(state)
  end

  @impl true
  def handle_info(:timeout, state) do
    handle_shutdown(state)
  end

  defp handle_shutdown({{id, _}, meta, model, _}=_state) do
    # unload everything
    Logger.info("channel-#{id} server: unloading")
    Meta.dump!(id, meta)
    Model.dump!(id, model)
    Logger.info("channel-#{id} server: unloaded")

    # exit
    :ets.delete(:channel_servers, id)
    exit(:normal)
  end



  # ===== API =====



  def boot do
    :ets.new(:channel_servers, [:set, :named_table, :public])
    Logger.debug("created channel_servers table")
  end

  def start({id, guild}=arg) when is_integer(id) and is_integer(guild) do
    {:ok, pid} = GenServer.start_link(__MODULE__, arg)
    :ets.insert(:channel_servers, {id, pid})
    pid
  end

  def maybe_start({id, guild}=arg) when is_integer(id) and is_integer(guild) do
    case get_pid(id) do
      :nopid -> start(arg)
      pid -> pid
    end
  end

  def get_pid({id, gid}) when is_integer(id) and is_integer(gid) do
    case :ets.lookup(:channel_servers, id) do
      [{_, pid}] -> pid
      [] ->
        GuildServer.maybe_start(gid)
        start({id, gid})
    end
  end
  def get_pid(id) when is_integer(id) do
    case :ets.lookup(:channel_servers, id) do
      [{_, pid}] -> pid
      [] ->
        Logger.error("can't start non-existent channel-#{id} server because gid is unknown")
        :nopid
    end
  end

  @type server_id() :: integer() | {integer(), integer()}

  @spec get_meta(server_id()) :: %Meta{}
  def get_meta(id) when (is_integer(id) or is_tuple(id)) do
    get_pid(id) |> GenServer.call(:get_meta)
  end

  @spec get_model_stats(server_id()) :: %Model{}
  def get_model_stats(id) when (is_integer(id) or is_tuple(id)) do
    get_pid(id) |> GenServer.call(:get_model)
  end

  @spec handle_message(server_id(), String.t(), boolean(), integer()) :: :ok | {:message, String.t()}
  def handle_message(id, msg, by_bot, author_id) when (is_integer(id) or is_tuple(id)) and is_binary(msg) and is_boolean(by_bot) and is_integer(author_id) do
    get_pid(id) |> GenServer.call({:message, msg, by_bot, author_id})
  end

  @spec generate(server_id()) :: String.t()
  def generate(id) when (is_integer(id) or is_tuple(id)) do
    get_pid(id) |> GenServer.call(:generate)
  end

  @spec reset(server_id(), atom()) :: :ok
  def reset(id, what) when (is_integer(id) or is_tuple(id)) and is_atom(what) do
    get_pid(id) |> GenServer.call({:reset, what})
  end

  @spec set(server_id(), atom(), any()) :: :ok
  def set(id, setting, value) when (is_integer(id) or is_tuple(id)) and is_atom(setting) do
    get_pid(id) |> GenServer.call({:set, setting, value})
  end

  @spec shutdown(server_id()) :: :ok
  def shutdown(id) when (is_integer(id) or is_tuple(id)) do
    get_pid(id) |> GenServer.call(:shutdown)
  end
end
