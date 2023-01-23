defmodule Deutexrium.Server.Channel do
  @moduledoc """
  Keeps track of channel data and settings, as well as manages generation
  and training of the associated Markov model
  """

  @url_regex ~r"(((ht|f)tp(s?))\://)?(www.|[a-zA-Z].)[a-zA-Z0-9\-\.]+\.(com|edu|gov|mil|net|org|biz|info|name|museum|us|ca|uk)(\:[0-9]+)*(/($|[a-zA-Z0-9\.\,\;\?\'\\\+&%\$#\=~_\-]+))*"

  use GenServer
  require Logger
  alias Deutexrium.Persistence.Meta
  alias Deutexrium.Persistence
  alias Deutexrium.Server
  alias Server.RqRouter

  defmodule State do
    @moduledoc false
    defstruct [:id, :meta, :model, :timeout, :pre_train]
    @type t :: %__MODULE__{
      id: {channel :: non_neg_integer(), guild :: non_neg_integer()},
      meta: Meta.t(),
      model: Markov.model_reference,
      timeout: non_neg_integer(),
      pre_train: nil
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

    path = Persistence.root_for(id)
    model = case Markov.load(Persistence.root_for(id), [
      # default model options
      sanitize_tokens: true,
      order: 3,
      shift_probabilities: true,
      store_log: [:train, :gen, :start, :end]
    ]) do
      {:ok, model} -> model
      {:error, {:already_started, pid}} -> {:via, Registry, {Markov.ModelServers, path}}
    end

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
      timeout: timeout,
      pre_train: nil
    }, timeout}
  end

  def handle_call(:get_meta, _from, state), do:
    {:reply, state.meta, state, state.timeout}
  def handle_call(:get_model, _from, state), do:
    {:reply, state.model, state, state.timeout}

  def handle_call({:message, msg}, _from, state) do
    # train unless the message was sent by a bot and the corresponding settings prohibits that
    if not (msg.author.bot || false) or not get_setting(state, :ignore_bots) do
      # check training settings
      {cid, guild} = state.id
      train = cid == 0 or get_setting(state, :train)
      global_train = cid != 0 and get_setting(state, :global_train)

      # save attachments
      attachments = (msg.attachments |> Enum.map(fn x -> x.url end))
        ++ (Regex.scan(@url_regex, msg.content) |> Enum.map(fn [str|_] -> str end))

      File.open!(Persistence.root_for(cid) |> Path.join("media.list"), [:utf8, :append], fn file ->
        IO.write(file, ["\n" | attachments |> Enum.join("\n")])
      end)

      # train local model
      state = if train and byte_size(msg.content) > 0 do
        Logger.info("channel-#{cid} server: training local model")
        Markov.Prompt.train(state.model, "#{msg.author.id} #{msg.content}", state.meta.last_message, [{:author, msg.author.id}])
        %{state | meta: %{state.meta | total_msgs: state.meta.total_msgs + 1}}
      else state end

      # train global model
      state = if global_train and byte_size(msg.content) > 0 do
        Logger.info("channel-#{cid} server: training global model")
        handle_message({0, 0}, msg.content)
        %{state | meta: %{state.meta | global_trained_on: state.meta.global_trained_on + 1}}
      else state end

      # auto-generation
      autorate = get_setting(state, :autogen_rate)
      reply = if (autorate > 0) and (:rand.uniform() <= 1.0 / autorate) do
        Logger.info("channel-#{cid} server: automatic generation")
        filter = cid == 0 or get_setting(state, :remove_mentions)
        result = generate_message(state.model, filter, msg.content)
        {:message, result}
      else :ok end

      # scoreboard
      Server.Guild.scoreboard_add_one(guild, msg.author.id)

      {:reply, reply, %{state | meta: %{state.meta | last_message: msg.content}}, state.timeout}
    else
      {:reply, :ok, state, state.timeout}
    end
  end

  def handle_call({:message, :bare, msg}, _from, state) do
    Markov.Prompt.train(state.model, "0 #{msg}", state.meta.last_message, [{:author, 0}])
    {:reply, :ok, %{state | meta: %{state.meta | last_message: msg}}, state.timeout}
  end

  def handle_call({:generate, user_id, prompt}, _from, state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: generating on demand")
    filter = cid == 0 or get_setting(state, :remove_mentions)
    {:reply, generate_message(state.model, filter, prompt, user_id), state, state.timeout}
  end

  def handle_call({:start_pre_train, inter, count, locale}, _from, state) do
    {cid, _} = state.id

    Logger.info("channel-#{cid} server: starting pre-train")
    state = %{state | pre_train: {inter, {0, count, 0}, DateTime.utc_now |> Nostrum.Snowflake.from_datetime!, nil, locale}}
    send(self(), :continue_pre_train)
    send_pre_train_status(:working, state.pre_train)

    {:reply, :ok, state, state.timeout}
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
    Markov.unload(state.model)
    File.rm_rf(Persistence.root_for(cid))
    Logger.info("channel-#{cid} server: model reset")
    {:stop, {:shutdown, :reset}, :ok, state}
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

  def handle_info(:continue_pre_train, %State{id: {cid, _}} = state) do
    {inter, {fetched, limit, skipped}, before, last, locale} = state.pre_train
    batch_size = Application.fetch_env!(:deutexrium, :pre_train_batch_size)
    requesting = min(limit - fetched, batch_size)

    state = case Nostrum.Api.get_channel_messages(cid, requesting, {:before, before}) do
      {:ok, messages} ->
        Logger.info("channel-#{cid} server: pre_train: got #{length(messages)} messages")
        messages = Enum.reverse([last | messages])

        [last | _] = for pair <- Markov.ListUtil.overlapping_stride(messages, 2) do
          case pair do
            [nil, nil] ->
              nil

            [a, b] when a.content == "" ->
              b

            [a, nil] ->
              Markov.train(state.model, "#{a.author.id} #{a.content}", [{:author, a.author.id}])
              a

            [a, b] ->
              Markov.Prompt.train(state.model, "#{a.author.id} #{a.content}", "#{b.author.id} #{b.content}", [{:author, a.author.id}])
              a
          end
        end

        skipped_in_batch = Enum.count(messages, fn x -> x != nil and x.content == "" end)
        fetched = fetched + length(messages) - 1 - skipped_in_batch
        skipped = skipped + skipped_in_batch
        before = if Enum.at(messages, 0) != nil, do: Enum.at(messages, 0).id, else: before
        state = %{state |
          pre_train: {inter, {fetched, limit, skipped}, before, last, locale},
          meta: %{state.meta |
            total_msgs: state.meta.total_msgs + length(messages) - 1 - skipped_in_batch
          }
        }

        if length(messages) == requesting + 1 do
          send_pre_train_status(:working, state.pre_train)
          send(self(), :continue_pre_train)
          state
        else
          send_pre_train_status(:done, state.pre_train)
          %{state | pre_train: nil}
        end

      _ when requesting < 1 ->
        send_pre_train_status(:done, state.pre_train)
        %{state | pre_train: nil}

      err ->
        Logger.error("channel-#{cid} server: pre_train: failed to fetch messages #{inspect err}")
        send_pre_train_status(:error, state.pre_train)
        %{state | pre_train: nil}
    end

    {:noreply, state}
  end

  def terminate({:shutdown, :reset}, _state), do: :ok
  def terminate(_reason, state), do: dump(state)

  defp dump(%State{} = state) do
    {cid, _} = state.id
    Logger.info("channel-#{cid} server: unloading")
    Meta.dump!(cid, state.meta)
    Markov.unload(state.model)
    Logger.info("channel-#{cid} server: unloaded")
  end

  defp send_pre_train_status(status, {inter, {fetched, limit, skipped}, _, _, locale}) do
    emoji = cond do
      status == :working -> ":arrows_clockwise:"
      status == :done and fetched == 0 -> ":question:"
      status == :done -> ":white_check_mark:"
      status == :error -> ":x:"
    end

    percent = div(fetched * 100, limit)
    full_bars = div(percent, 5)
    empty_bars = 20 - full_bars
    bar = "(#{String.duplicate("━", full_bars)}#{String.duplicate("┈", empty_bars)}) #{percent}%"

    bar = cond do
      status == :done and fetched == 0 ->
        "#{bar}\n#{Deutexrium.Translation.translate(locale, "response.pre_train.hint.empty")}"
      status == :done and fetched < limit ->
        "#{bar}\n*#{Deutexrium.Translation.translate(locale, "response.pre_train.hint.okay")}*"
      status == :error ->
        "#{bar}\n*#{Deutexrium.Translation.translate(locale, "response.pre_train.error.fetch_failed")}*"
      true -> bar
    end

    string = Deutexrium.Translation.translate(locale, "response.pre_train.progress",
      [emoji, "#{fetched}", "#{limit}", "#{skipped}", bar])
    Nostrum.Api.edit_interaction_response(inter, %{content: string})
  end

  # ===== API =====

  @type server_id() :: {integer(), integer()}

  @spec get_meta(server_id()) :: Meta.t()
  def get_meta(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_meta)

  @spec get_model(server_id()) :: Model.t()
  def get_model(id) when is_tuple(id), do: id |> RqRouter.route_to_chan(:get_model)

  @spec handle_message(Nostrum.Struct.Message.t) :: :ok | {:message, {String.t(), integer()}}
  def handle_message(msg), do: {msg.channel_id, msg.guild_id} |> RqRouter.route_to_chan({:message, msg})
  @spec handle_message(server_id(), String.t) :: :ok | {:message, {String.t(), integer()}}
  def handle_message(id, text), do: id |> RqRouter.route_to_chan({:message, :bare, text})

  @spec generate(server_id(), integer() | nil, String.t() | nil) :: {String.t(), integer()} | :error
  def generate(id, user_id \\ nil, prompt \\ nil) when is_tuple(id) do
    id |> RqRouter.route_to_chan({:generate, user_id, prompt})
  end

  def start_pre_train(id, inter, count, locale) when is_tuple(id) and is_integer(count) do
    id |> RqRouter.route_to_chan({:start_pre_train, inter, count, locale})
  end

  @spec reset(server_id(), atom()) :: :ok
  def reset(id, what) when is_tuple(id) and is_atom(what), do: id |> RqRouter.route_to_chan({:reset, what})

  @spec set(server_id(), atom(), any()) :: :ok
  def set(id, setting, value) when is_tuple(id) and is_atom(setting), do:
    id |> RqRouter.route_to_chan({:set, setting, value})

  @spec get(server_id(), atom()) :: any()
  def get(id, setting) when is_tuple(id) and is_atom(setting), do: id |> RqRouter.route_to_chan({:get, setting})

  @spec get_file(server_id(), Regex.t) :: String.t
  def get_file({id, _}, path_pattern \\ ~r/.*/) do
    uri_list = File.read!(Persistence.root_for(id) |> Path.join("media.list"))
      |> String.split("\n")
      |> Enum.filter(fn x ->
        x != "" and String.match?(URI.new!(x).path, path_pattern)
      end)

    n = :rand.uniform(length(uri_list)) - 1
    uri_list |> Enum.at(n)
  end
end
