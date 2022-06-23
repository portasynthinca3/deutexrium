defmodule Deutexrium.Server.Channel do
  @moduledoc """
  Keeps track of channel data and settings, as well as manages generation
  and training of the associated Markov model
  """

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

  defp generate_message(%Markov{} = model, sentiment, filter, author \\ nil) do
    try do
      start = cond do
        author == nil and sentiment == :nosentiment -> [:start, :start]
        author != nil and sentiment == :nosentiment -> [{:sentiment, :neutral}, {:author, author}]
        author == nil and sentiment != :nosentiment -> [:start, {:sentiment, sentiment}]
        author != nil and sentiment != :nosentiment -> [{:sentiment, sentiment}, {:author, author}]
      end

      # generate tokens
      tokens = model |> Markov.generate_tokens(start -- [:start, :start], start)
      [{:sentiment, sentiment}, {:author, author} | text_tokens] = tokens
      Deutexrium.Influx.LoadCntr.add(:gen)

      # filter message
      text = text_tokens |> Enum.join(" ")
      text = if filter do
        no_mentions = Regex.replace(~r/<(#|@|@&|@!)[0-9]+>/, text, "**[mention removed]**")
        Regex.replace(~r/https?:\/\/.*\b/, no_mentions, "**[link removed]**")
      else text end

      {author, sentiment, text}
    rescue
      _ -> :error
    end
  end

  defp train_model(%Model{} = model, text, author) do
    sentiment = Sentiment.detect(text)
    markov = model.data |> Markov.train([{:sentiment, sentiment}, {:author, author} | text |> String.split])
    Deutexrium.Influx.LoadCntr.add(:train)
    %{model |
      data: markov,
      trained_on:
      model.trained_on + 1,
      messages: [{author, text} | model.messages]
    }
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
  def handle_call(:get_meta, _from, {_, meta, _, timeout} = state) do
    {:reply, meta, state, timeout}
  end
  @impl true
  def handle_call(:get_model, _from, {_, _, model, timeout} = state) do
    {:reply, Map.delete(model, :data), state, timeout}
  end

  @impl true
  def handle_call({:message, message, by_bot, author_id}, _from, {{cid, guild} = id, meta, model, timeout} = state) do
    # don't train if ignoring bots
    # credo:disable-for-next-line
    unless by_bot and get_setting({id, meta}, :ignore_bots) do
      # check training settings
      train = cid == 0 or get_setting({id, meta}, :train)
      global_train = id != 0 and get_setting({id, meta}, :global_train)

      # train local model
      sentiment = Sentiment.detect(message)
      model = if train do
        Logger.info("channel-#{cid} server: training local model sentiment=#{inspect sentiment}")
        train_model(model, message, author_id)
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
      reply = if (autorate > 0) and (:rand.uniform() <= 1.0 / autorate) do
        Logger.info("channel-#{cid} server: automatic generation with sentiment=#{inspect sentiment}")
        filter = cid == 0 or get_setting({id, meta}, :remove_mentions)
        params = generate_message(model.data, sentiment, filter)
        {:message, params}
      else
        :ok
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
  def handle_call({:generate, sentiment, author}, _from, {{cid, _} = id, meta, model, timeout} = state) do
    Logger.info("channel-#{cid} server: generating on demand with sentiment=#{inspect sentiment} and author=#{inspect author}")
    filter = cid == 0 or get_setting({id, meta}, :remove_mentions)
    case generate_message(model.data, sentiment, filter, author) do
      {a, s, text} ->{:reply, {a, s, text}, state, timeout}
      _ -> {:reply, :error, state, timeout}
    end
  end

  @impl true
  def handle_call({:reset, :settings}, _from, {{cid, _} = id, _, model, timeout}) do
    Logger.info("channel-#{cid} server: settings reset")
    {:reply, :ok, {id, %Meta{}, model, timeout}, timeout}
  end
  @impl true
  def handle_call({:reset, :model}, _from, {{cid, _} = id, meta, _, timeout}) do
    Logger.info("channel-#{cid} server: model reset")
    {:reply, :ok, {id, meta, %Model{}, timeout}, timeout}
  end

  @impl true
  def handle_call({:set, setting, val}, _from, {{cid, _} = id, meta, model, timeout}) do
    Logger.info("channel-#{cid} server: settings changed")
    {:reply, :ok, {id, Map.put(meta, setting, val), model, timeout}, timeout}
  end

  @impl true
  def handle_call({:get, setting}, _from, {id, meta, _, timeout} = state) do
    {:reply, get_setting({id, meta}, setting), state, timeout}
  end

  @impl true
  def handle_call(:token_stats, _from, {_, _, model, timeout} = state) do
    {:reply, MarkovTool.token_stats(model.data), state, timeout}
  end

  @impl true
  def handle_call({:forget, token}, _from, {{cid, _} = id, meta, model, timeout}) do
    Logger.info("channel-#{cid} server: forgetting token")
    {:reply, :ok,
      {id, meta, %{model |
        data: Markov.forget_token(model.data, token),
        forget_operations: [token | model.forget_operations]}, timeout},
    timeout}
  end

  @impl true
  def handle_call({:export, format}, _from, {{cid, _}, meta, model, timeout} = state) do
    Logger.info("channel-#{cid} server: exporting in #{inspect format}")
    encode = case format do
      :etf_gz -> &(&1 |> :erlang.term_to_binary |> :zlib.gzip())
      :json -> &Jason.encode!/1
      :bson -> &Cyanide.encode!/1
    end
    {:reply, {encode.(meta), encode.(model)}, state, timeout}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    dump(state)
    {:stop, :shutdown, :ok, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    dump(state)
    {:stop, :shutdown, state}
  end

  defp dump({{id, _}, meta, model, _} = _state) do
    Logger.info("channel-#{id} server: unloading")
    Meta.dump!(id, meta)
    Model.dump!(id, model)
    Logger.info("channel-#{id} server: unloaded")
  end

  # ===== API =====

  @type server_id() :: {integer(), integer()}
  @type gen_result() :: {integer(), Sentiment.sentiment(), String.t()}

  @spec get_meta(server_id()) :: Meta.t()
  def get_meta(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_meta)

  @spec get_model_stats(server_id()) :: Model.t()
  def get_model_stats(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_model)

  @spec handle_message(server_id(), String.t(), boolean(), integer()) :: :ok | {:message, gen_result()}
  def handle_message(id, msg, by_bot, author_id) when is_tuple(id) and is_binary(msg) and is_boolean(by_bot) and is_integer(author_id) do
    id |> RqRouter.route_to_chan({:message, msg, by_bot, author_id})
  end

  @spec generate(server_id(), Sentiment.sentiment(), integer()|nil) :: gen_result()|:error
  def generate(id, sentiment \\ :nosentiment, author \\ nil) when is_tuple(id) do
    id |> RqRouter.route_to_chan({:generate, sentiment, author})
  end

  @spec reset(server_id(), atom()) :: :ok
  def reset(id, what) when is_tuple(id) and is_atom(what), do: id |> RqRouter.route_to_chan({:reset, what})

  @spec set(server_id(), atom(), any()) :: :ok
  def set(id, setting, value) when is_tuple(id) and is_atom(setting), do:
    id |> RqRouter.route_to_chan({:set, setting, value})

  @spec get(server_id(), atom()) :: any()
  def get(id, setting) when is_tuple(id) and is_atom(setting), do: id |> RqRouter.route_to_chan({:get, setting})

  @spec token_stats(server_id()) :: String.t()
  def token_stats(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:token_stats)

  @spec forget(server_id(), String.t()) :: :ok
  def forget(id, token) when is_tuple(id), do: id |> RqRouter.route_to_chan({:forget, token})

  @spec export(server_id(), atom()) :: binary()
  def export(id, format) when is_tuple(id), do: id |> RqRouter.route_to_chan({:export, format})
end
