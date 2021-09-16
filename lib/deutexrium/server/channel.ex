defmodule Deutexrium.Server.Channel do
  use GenServer
  require Logger
  alias Deutexrium.Persistence.{Meta, Model}
  alias Deutexrium.Server
  alias Server.RqRouter

  defp get_setting({{_, guild}, meta}, setting) do
    if Map.get(meta, setting) == nil do
      Server.Guild.get_meta(guild) |> Map.get(setting)
    else
      Map.get(meta, setting)
    end
  end

  # these two wrappers exist to allow keeping track of the author

  defp generate_message(%Markov{}=model, authored_only) do
    tokens = model |> Markov.generate_tokens([], if authored_only do [:start, :from] else [:start, :start] end)
    {author, tokens} = case tokens do
      [:from, id | rest] -> {id, rest}
      [id | rest] when authored_only -> {id, rest}
      _ -> {:noauthor, tokens}
    end
    {author, tokens |> Enum.join(" ")}
  end

  defp train_model(%Markov{}=model, text, author) do
    model |> Markov.train([:from, author | text |> String.split])
  end

  defp likely_authored(%Markov{}=model) do
    first_tokens = model.links |> Map.get([:start, :start])
    contains_token = first_tokens |> Map.get(:from, 0)
    other_sum = first_tokens |> Enum.reduce(0, fn {k, v}, acc ->
      if k == :from do
        acc
      else
        acc + v
      end
    end)
    contains_token / (contains_token + other_sum)
  end



  @impl true
  def init({id, guild}) do
    # load model and meta
    Logger.info("channel-#{id} server: loading")
    meta = try do
      Meta.load!(id)
    rescue
      _ ->
        Logger.info("channel-#{id} server: creating new meta")
        Meta.dump!(id, %Meta{})
        %Meta{}
    end
    model = try do
      Model.load!(id)
    rescue
      _ ->
        Logger.info("channel-#{id} server: creating new model")
        Model.dump!(id, %Model{})
        %Model{}
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
    {:reply,
      Map.delete(model, :data) |>
      Map.put(:likely_authored, likely_authored(model.data)),
    state, timeout}
  end

  @impl true
  def handle_call({:message, message, by_bot, author_id}, _from, {{cid, guild}=id, meta, model, timeout}=state) do
    # don't train if ignoring bots
    unless by_bot and get_setting({id, meta}, :ignore_bots) do
      # check training settings
      train = id == 0 or get_setting({id, meta}, :train)
      global_train = id != 0 and get_setting({id, meta}, :global_train)

      # train local model
      model = if train do
        Logger.info("channel-#{cid} server: training local model")
        %{model | data: train_model(model.data, message, author_id),
          trained_on: model.trained_on + 1}
      else model
      end

      # train global model
      model = if global_train do
        Logger.info("channel-#{cid} server: training global model")
        handle_message({0, 0}, message, false, 0)
        %{model | global_trained_on: model.global_trained_on + 1}
      else model
      end

      # auto-generation
      autorate = get_setting({id, meta}, :autogen_rate)
      reply = cond do
        (autorate > 0) and (:rand.uniform() <= 1.0 / autorate) ->
          Logger.info("channel-#{cid} server: automatic generation")
          {:message, {_,_}=generate_message(model.data, get_setting({id, meta}, :force_authored))}

        true -> :ok
      end

      # scoreboard
      Server.Guild.scoreboard_add_one(guild, author_id)

      {:reply, reply,
        {id, %{meta | total_msgs: meta.total_msgs + 1}, model, timeout}, timeout}
    else
      {:reply, :ok, state, timeout}
    end
  end

  @impl true
  def handle_call(:generate, _from, {{cid, _}, _, model, timeout}=state) do
    {_, text} = generate_message(model.data, false)

    # remove mentions in global model
    text = if cid == 0 do
      Regex.replace(~r/<@!{0,1}[0-9]*>/, text, "**[mention removed]**")
    else text end

    Logger.info("channel-#{cid} server: generating on demand")
    {:reply, text, state, timeout}
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
  def handle_call({:set, setting, val}, _from, {{cid, _}=id, meta, model, timeout}) do
    Logger.info("channel-#{cid} server: settings changed")
    {:reply, :ok, {id, Map.put(meta, setting, val), model, timeout}, timeout}
  end

  @impl true
  def handle_call({:get, setting}, _from, {id, meta, _, timeout}=state) do
    {:reply, get_setting({id, meta}, setting), state, timeout}
  end

  @impl true
  def handle_call(:token_stats, _from, {_, _, model, timeout}=state) do
    {:reply, MarkovTool.token_stats(model.data), state, timeout}
  end

  @impl true
  def handle_call({:forget, token}, _from, {{cid, _}=id, meta, model, timeout}) do
    Logger.info("channel-#{cid} server: forgetting token")
    {:reply, :ok, {id, meta, %{model | data: MarkovTool.forget_token(model.data, token)}, timeout}, timeout}
  end

  @impl true
  def handle_cast({:shutdown, freeze}, {{id, _}, _, _, _}=state) do
    handle_shutdown(state, not freeze)
    if freeze do
      Logger.notice("channel-#{id} server: freezing")
      infinite_loop()
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    handle_shutdown(state, true)
  end

  defp handle_shutdown({{id, _}, meta, model, _}=_state, do_exit) do
    # unload everything
    Logger.info("channel-#{id} server: unloading")
    Meta.dump!(id, meta)
    Model.dump!(id, model)
    Logger.info("channel-#{id} server: unloaded")

    # exit
    if do_exit do
      exit(:normal)
    end
  end

  defp infinite_loop do
    infinite_loop()
  end



  # ===== API =====





  @type server_id() :: {integer(), integer()}

  @spec get_meta(server_id()) :: %Meta{}
  def get_meta(id) when (is_integer(id) or is_tuple(id)) do
    id |> RqRouter.route_to_chan(:get_meta)
  end

  @spec get_model_stats(server_id()) :: %Model{}
  def get_model_stats(id) when (is_integer(id) or is_tuple(id)) do
    id |> RqRouter.route_to_chan(:get_model)
  end

  @spec handle_message(server_id(), String.t(), boolean(), integer()) :: :ok | {:message, String.t()}
  def handle_message(id, msg, by_bot, author_id) when (is_integer(id) or is_tuple(id)) and is_binary(msg) and is_boolean(by_bot) and is_integer(author_id) do
    id |> RqRouter.route_to_chan({:message, msg, by_bot, author_id})
  end

  @spec generate(server_id()) :: String.t()
  def generate(id) when (is_integer(id) or is_tuple(id)) do
    id |> RqRouter.route_to_chan(:generate)
  end

  @spec reset(server_id(), atom()) :: :ok
  def reset(id, what) when (is_integer(id) or is_tuple(id)) and is_atom(what) do
    id |> RqRouter.route_to_chan({:reset, what})
  end

  @spec set(server_id(), atom(), any()) :: :ok
  def set(id, setting, value) when (is_integer(id) or is_tuple(id)) and is_atom(setting) do
    id |> RqRouter.route_to_chan({:set, setting, value})
  end

  @spec get(server_id(), atom()) :: any()
  def get(id, setting) when (is_integer(id) or is_tuple(id)) and is_atom(setting) do
    id |> RqRouter.route_to_chan({:get, setting})
  end

  @spec token_stats(server_id()) :: String.t()
  def token_stats(id) when (is_integer(id) or is_tuple(id)) do
    id |> RqRouter.route_to_chan(:token_stats)
  end

  @spec get(server_id(), atom()) :: :ok
  def forget(id, token) when is_integer(id) or is_tuple(id) do
    id |> RqRouter.route_to_chan({:forget, token})
  end
end
