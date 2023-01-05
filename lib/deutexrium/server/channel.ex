defmodule Deutexrium.Server.Channel do
  @moduledoc """
  Keeps track of channel data and settings, as well as manages generation
  and training of the associated Markov model
  """

  use GenServer
  require Logger
  alias Deutexrium.Persistence.Meta
  alias Deutexrium.Persistence
  alias Deutexrium.Server
  alias Server.RqRouter

  defmodule State do
    defstruct [:id, :meta, :model, :timeout]
    @type t :: %__MODULE__{
      id: {channel :: non_neg_integer(), guild :: non_neg_integer()},
      meta: Meta.t(),
      model: Markov.model_reference,
      timeout: non_neg_integer()
    }
  end

  @spec get_setting(state :: State.t(), setting :: Meta.channel_setting()) :: any()
  defp get_setting(state, setting) do
    {_, guild} = state.id
    if Map.get(state.meta, setting) == nil do
      Server.Guild.get_meta(guild) |> Map.get(setting)
    else
      Map.get(state.meta, setting)
    end
  end

  @spec generate_message(model :: Markov.model_reference(), filter :: boolean(),
    prompt :: String.t() | nil, author_id :: integer() | nil) :: {String.t(), integer()} | :error
  defp generate_message(model, filter, prompt, author_id \\ nil) do
    query = if author_id, do: %{{:author, author_id} => 1000}, else: %{}

    Deutexrium.Influx.LoadCntr.add(:gen)
    result = if prompt, do:
      Markov.Prompt.generate_prompted(model, prompt, query), else:
      Markov.generate_text(model, query)

    case result do
      {:ok, text} ->
        # split into author id and text
        [author_id | _] = String.split(text)
        text = String.slice(text, byte_size(author_id)+1..-1)
        {author_id, _} = Integer.parse(author_id)

        # filter message
        text = if filter do
          no_mentions = Regex.replace(~r/<(#|@|@&|@!)[0-9]+>/, text, "**[mention removed]**")
          Regex.replace(~r/https?:\/\/.*\b/, no_mentions, "**[link removed]**")
        else text end

        {text, author_id}

      {:error, error} ->
        Logger.error("channel-#{} server: error generating: #{inspect error}")
        :error
    end
  end

  def init({id, guild}) do
    Process.flag(:trap_exit, true)

    # load meta and model
    Logger.info("channel-#{id} server: loading")

    {:ok, model} = Markov.load(Persistence.root_for(id), [
      # default model options
      sanitize_tokens: true,
      order: 3,
      shift_probabilities: true,
      store_log: [:train, :gen, :start, :end]
    ])

    meta = try do
      Meta.load!(id)
    rescue
      _ ->
        Logger.info("channel-#{id} server: creating new meta")
        Meta.dump!(id, %Meta{})
        %Meta{}
    end

    Logger.info("channel-#{id} server: loaded")
    timeout = Application.fetch_env!(:deutexrium, :channel_unload_timeout)
    {:ok, %State{
      id: {id, guild},
      model: model,
      meta: meta,
      timeout: timeout
    }, timeout}
  end

  def handle_call(:get_meta, _from, state), do:
    {:reply, state.meta, state, state.timeout}
  def handle_call(:get_model, _from, state), do:
    {:reply, state.model, state, state.timeout}

  def handle_call({:message, message, by_bot, author_id}, _from, state) do
    # don't train if ignoring bots
    # credo:disable-for-next-line
    unless by_bot and get_setting(state, :ignore_bots) do
      # check training settings
      {cid, guild} = state.id
      train = cid == 0 or get_setting(state, :train)
      global_train = cid != 0 and get_setting(state, :global_train)

      # train local model
      state = if train do
        Logger.info("channel-#{cid} server: training local model")
        Markov.Prompt.train(state.model, "#{author_id} #{message}", state.meta.last_message, [{:author, author_id}])
        Deutexrium.Influx.LoadCntr.add(:train)
        %{state | meta: %{state.meta | total_msgs: state.meta.total_msgs + 1}}
      else state end

      # train global model
      state = if global_train do
        Logger.info("channel-#{cid} server: training global model")
        handle_message({0, 0}, message, false, 0)
        %{state | meta: %{state.meta | global_trained_on: state.meta.global_trained_on + 1}}
      else state end

      # auto-generation
      autorate = get_setting(state, :autogen_rate)
      reply = if (autorate > 0) and (:rand.uniform() <= 1.0 / autorate) do
        Logger.info("channel-#{cid} server: automatic generation")
        filter = cid == 0 or get_setting(state, :remove_mentions)
        result = generate_message(state.model, filter, message)
        {:message, result}
      else :ok end

      # scoreboard
      Server.Guild.scoreboard_add_one(guild, author_id)

      {:reply, reply, %{state | meta: %{state.meta | last_message: message}}, state.timeout}
    else
      {:reply, :ok, state, state.timeout}
    end
  end

  def handle_call({:generate, user_id, prompt}, _from, state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: generating on demand")
    filter = cid == 0 or get_setting(state, :remove_mentions)
    {:reply, generate_message(state.model, filter, prompt, user_id), state, state.timeout}
  end

  def handle_call({:reset, :settings}, _from, state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: settings reset")
    {:reply, :ok, %{state | meta: %Meta{
      total_msgs: state.meta.total_msgs,
      global_trained_on: state.meta.global_trained_on
    }}, state.timeout}
  end
  def handle_call({:reset, :model}, _from, state) do
    {cid, _} = state.id
    state = %{state | meta: %{state.meta | total_msgs: 0, global_trained_on: 0}}
    File.rm_rf(Persistence.root_for(cid))
    Logger.info("channel-#{cid} server: model reset")
    {:stop, :reset, :ok, state}
  end

  def handle_call({:set, setting, val}, _from, state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: settings changed")
    {:reply, :ok, %{state | meta: Map.put(state.meta, setting, val)}, state.timeout}
  end

  def handle_call({:get, setting}, _from, state) do
    {:reply, get_setting(state, setting), state, state.timeout}
  end

  def handle_call(:shutdown, _from, state), do: {:stop, :shutdown, :ok, state}
  def handle_info(:timeout, state), do: {:stop, :shutdown, state}

  def terminate(:reset, _state), do: :ok
  def terminate(_reason, state), do: dump(state)

  defp dump(%State{} = state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: unloading")
    Meta.dump!(cid, state.meta)
    Markov.unload(state.model)
    Logger.info("channel-#{cid} server: unloaded")
  end

  # ===== API =====

  @type server_id() :: {integer(), integer()}

  @spec get_meta(server_id()) :: Meta.t()
  def get_meta(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_meta)

  @spec get_model(server_id()) :: Model.t()
  def get_model(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_model)

  @spec handle_message(server_id(), String.t(), boolean(), integer()) :: :ok | {:message, {String.t(), integer()}}
  def handle_message(id, msg, by_bot, author_id) when is_tuple(id) and is_binary(msg) and is_boolean(by_bot) and is_integer(author_id) do
    id |> RqRouter.route_to_chan({:message, msg, by_bot, author_id})
  end

  @spec generate(server_id(), integer() | nil, String.t() | nil) :: {String.t(), integer()} | :error
  def generate(id, user_id \\ nil, prompt \\ nil) when is_tuple(id) do
    id |> RqRouter.route_to_chan({:generate, user_id, prompt})
  end

  @spec reset(server_id(), atom()) :: :ok
  def reset(id, what) when is_tuple(id) and is_atom(what), do: id |> RqRouter.route_to_chan({:reset, what})

  @spec set(server_id(), atom(), any()) :: :ok
  def set(id, setting, value) when is_tuple(id) and is_atom(setting), do:
    id |> RqRouter.route_to_chan({:set, setting, value})

  @spec get(server_id(), atom()) :: any()
  def get(id, setting) when is_tuple(id) and is_atom(setting), do: id |> RqRouter.route_to_chan({:get, setting})
end
