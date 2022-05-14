defmodule Deutexrium do
  @moduledoc """
  Accepts data from Nostrum and invokes Channel, Guild and Voice servers'
  functions accordingly.
  """

  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct
  import Nostrum.Struct.Embed
  alias Deutexrium.Server

  @missing_privilege ":x: **missing \"administrator\" privilege**\n[More info](https://deut.portasynthinca3.me/admin-cmd/admin-commands-notice)"

  def update_presence do
    Logger.info("updating presence")
    guild_cnt = Nostrum.Cache.GuildCache.all() |> Enum.count()
    Api.update_status("", "#{guild_cnt} servers", 2)
  end

  def presence_updater do
    # update presence every 60s
    receive do after 60 * 1000 ->
      update_presence()
      presence_updater()
    end
  end



  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _, _}) do
    spawn(&presence_updater/0)
    spawn(&Deutexrium.Influx.Logger.log/0)
    Logger.info("ready")
  end



  def handle_event({:MESSAGE_CREATE, %Struct.Message{} = msg, _}) do
    self = msg.author.id == Nostrum.Cache.Me.get().id
    unless self or msg.guild_id == nil or msg.channel_id == nil or byte_size(msg.content) == 0 do
      # print metadata
      if msg.content == "deut_debug" and msg.author.id in Application.fetch_env!(:deutexrium, :debug_people) do
        Api.create_message(msg.channel_id, content: """
        channel metadata
        ```elixir
        #{inspect Server.Channel.get_meta({msg.channel_id, msg.guild_id})}
        ```
        guild metadata
        ```elixir
        #{inspect Server.Guild.get_meta(msg.guild_id)}
        ```
        """)
      end

      # react to mentions
      bot_id = Nostrum.Cache.Me.get().id
      possible_mentions = ["<@#{bot_id}>", "<@!#{bot_id}>"]
      if String.contains?(msg.content, possible_mentions) do
        sent = Sentiment.detect(msg.content)
        Logger.debug("mentioned with sentiment=#{inspect sent}")
        case Server.Channel.generate({msg.channel_id, msg.guild_id}, sent) do
          {_, _, text} ->
            simulate_typing(text, msg.channel_id, false)
            Api.create_message(msg.channel_id, content: text, message_reference: %{message_id: msg.id})
          :error -> :ok
        end
      else
        # only train if it doesn't contain bot mentions
        case Server.Channel.handle_message({msg.channel_id, msg.guild_id}, msg.content, msg.author.bot || false, msg.author.id) do
          :ok -> :ok
          {:message, :error} -> :ok
          {:message, text} ->
            # see it it's impostor time
            impostor_rate = Server.Channel.get({msg.channel_id, msg.guild_id}, :impostor_rate)
            webhook_data = if (impostor_rate > 0) and (:rand.uniform() <= impostor_rate / 100.0) do
                Server.Channel.get_meta({msg.channel_id, msg.guild_id}).webhook_data
            else
              nil
            end
            try_sending_webhook(text, msg.channel_id, webhook_data, msg.guild_id)
        end
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen"}} = inter, _}) do
    id = {inter.channel_id, inter.guild_id}
    count = if inter.data.options == nil do
      1
    else
      [%{name: "count", value: val}] = inter.data.options
      if val in 1..Server.Channel.get(id, :max_gen_len) do val else 0 end
    end

    if count > 0 do
      try do
        text = 1..count
            |> Enum.map_join("\n", fn _ -> {_, _, t} = Server.Channel.generate(id)
                        t end)
        Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
      rescue
        _ -> Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **generation failed**"}})
      end
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **value too big**\n[More info](https://deut.portasynthinca3.me/admin-cmd/gen-less-than-number-greater-than)", flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_by", options: nil}} = inter, _}) do
    Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **you must supply the sentiment, author or both. For simple generation use [/gen](https://deut.portasynthinca3.me/commands/gen)**", flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_by", options: options}} = inter, _}) do
    id = {inter.channel_id, inter.guild_id}
    {sentiment, user} = case options do
      [%{name: "user", value: u}, %{name: "sentiment", value: s}] -> {s, u}
      [%{name: "sentiment", value: s}, %{name: "user", value: u}] -> {s, u}
      [%{name: "sentiment", value: s}] -> {s, nil}
      [%{name: "user", value: u}] -> {"nosentiment", u}
    end
    sentiment = :erlang.binary_to_existing_atom(sentiment)

    case Server.Channel.generate(id, sentiment, user) do
      {_, _, _} = data ->
        webhook = Server.Channel.get(id, :webhook_data)
        Api.create_interaction_response(inter, %{type: 4, data: %{content: case webhook do
          {_, _} -> ":white_check_mark: **the response will be sent shortly**"
          nil -> ":question: **the response will be sent as a normal message shortly. Try [/impostor](https://deut.portasynthinca3.me/admin-cmd/impostor)**"
        end, flags: 64}})
        try_sending_webhook(data, inter.channel_id, webhook, inter.guild_id)

      :error ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: cond do
          user != nil -> ":x: **I haven't heard anything `#{Sentiment.name(sentiment)}` from <@#{user}>**"
          user == nil -> ":x: **I haven't heard anything `#{Sentiment.name(sentiment)}` in this channel**"
        end, flags: 64}})
    end
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "Generate message by them", target_id: user_id}} = inter, _}) do
    id = {inter.channel_id, inter.guild_id}
    case Server.Channel.generate(id, :nosentiment, user_id) do
      {_, _, _} = data ->
        webhook = Server.Channel.get(id, :webhook_data)
        Api.create_interaction_response(inter, %{type: 4, data: %{content: case webhook do
          {_, _} -> ":white_check_mark: **the response will be sent shortly**"
          nil -> ":question: **the response will be sent as a normal message shortly. Try [/impostor](https://deut.portasynthinca3.me/admin-cmd/impostor)**"
        end, flags: 64}})
        try_sending_webhook(data, inter.channel_id, webhook, inter.guild_id)

      :error ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **I haven't heard anything from <@#{user_id}>**", flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_from", options: [%{name: "channel", value: channel}]}} = inter, _}) do
    {_, _, text} = Server.Channel.generate({channel, inter.guild_id})
    Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "join", options: [%{name: "channel", value: channel}, %{name: "language", value: lang}]}} = inter, _}) do
    case Server.Voice.join({channel, inter.guild_id}, lang) do
      :ok ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **joined** <##{channel}>", flags: 64}})
      {:error, :pay} ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **this feature is paid and costs 5 USD per month per server. Contact `porta#1746` if you want to use it or know why.**", flags: 64}})
      {:error, :text} ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: <##{channel}> **is not a voice channel**", flags: 64}})
      end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "ggen"}} = inter, _}) do
    {_, _, text} = Server.Channel.generate({0, 0})
    Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help"}} = inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium commands")
        |> put_color(0xe6f916)
        |> put_description("More extensive help information at https://deut.portasynthinca3.me/")
        |> put_url("https://deut.portasynthinca3.me/")

        |> put_field("REGULAR COMMANDS", "can be run by anybody")
        |> put_field("help", ":information_source: send this message", true)
        |> put_field("status", ":green_circle: show the current stats", true)
        |> put_field("stats", ":yellow_circle: show how much resources I use", true)
        |> put_field("gen <count>", ":1234: generate <count> (1 if omitted) messages using the current channel's model immediately", true)
        |> put_field("gen_by [sentiment] [@user]", ":face_with_monocle: generate a message with a specific sentiment and/or authorship using the current channel's model immediately", true)
        |> put_field("gen_from #channel", ":level_slider: immediately generate a message using the mentioned channel's model", true)
        |> put_field("ggen", ":rocket: immediately generate a message using the global model", true)
        |> put_field("donate", ":question: ways to support me", true)
        |> put_field("privacy", ":lock: my privacy policy", true)
        |> put_field("support", ":thinking: ways to get support", true)
        |> put_field("scoreboard", ":100: top-10 most active users in this server", true)
        |> put_field("join", ":loud_sound: join a voice channel", true)

        |> put_field("ADMIN COMMANDS", "can only be run by those with the \"administrator\" privilege")
        |> put_field("settings", ":gear: display the configuration modification menu", true)
        |> put_field("search <word>", ":mag: search for a word in the model", true)
        |> put_field("forget <word>", ":skull: forget a specific word", true)
        |> put_field("impostor", "<:amogus:887939317371138048> enable impersonation mode. **please read /help impostor before using**", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "donate"}} = inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Ways to support Deuterium")
        |> put_color(0xe6f916)

        |> put_field(":loudspeaker: tell your friends about the bot", "...or invite it to other servers")
        |> put_field(":money_mouth: donate on Patreon", "https://patreon.com/portasynthinca3")
        |> put_field(":money_mouth: donate via PayPal", "https://paypal.me/portasynthinca3")
        |> put_field(":speaking_head: vote on DBL", "https://top.gg/bot/733605243396554813/vote")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "privacy"}} = inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium privacy policy")
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/privacy-policy")

        |> put_field("1. SCOPE", ~S"""
           This message describes how the Deuterium Discord bot ("Deuterium", "the bot", "bot"), its creator ("I", "me") processes its Users' ("you") data.
           """)
        |> put_field("2. AUTHORIZATION", """
           When you authorize the bot, it is added as a member of the server you've chosen. It has no access to your profile, direct messages or anything that is not related to the selected server.
           """)
        |> put_field("3. DATA PROCESSING", """
           Deuterium receives messages it receives in server channels and processes them according to these rules:
           - if the channel has its "message collection" setting set to "on", it trains the model on this message and saves said model do disk
           - if the channel has its "global message collection" setting set to "on", it trains the global model on this message and saves said model do disk
           """)
        |> put_field("4. DATA STORAGE", """
           Deuterium stores the following data:
           - Channel settings and statistics (e.g. is message collection allowed, the total number of collected messages, etc.). This data can be viewed using the `/status` and `/settings` commands
           - Local Markov chain model which consists of a set of probabilities of one word coming after another word
           - Global Markov chain model which stores content described above
           - Channel, user and server IDs
           - User-to-message-count relationship for `/scoreboard`
           - Raw message content to re-train the models in case the format changes
           Deuterium does **not** store the following data:
           - User nicknames/tags
           - Any other data not mentioned in the list above
           """)
        |> put_field("5. CONTACTING", """
           Please refer to `/support`
           """)
        |> put_field("6. DATA REMOVAL", """
           Due to the nature of Markov chains, it's unfortunately not possible to remove a certain section of the data I store. Only the whole model can be reset.
           If you wish to reset the channel model, you may use the `/reset channel model` command.
           If you wish to reset the global model, please reach out to `/support`.
           """)
        |> put_field("7. DATA DISCLOSURE", """
           I do not disclose collected data to anyone. Furthermore, I do not look at it myself.
           """)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "support"}} = inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium support")
        |> put_color(0xe6f916)
        |> put_field(":eye: Support server", "https://discord.gg/N52uWgD")
        |> put_field(":e_mail: Email", "`portasynthinca3 (at) gmail.com`")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "status"}} = inter, _}) do
    chan_model = Server.Channel.get_model_stats({inter.channel_id, inter.guild_id})
    global_model = Server.Channel.get_model_stats({0, 0})

    embed = %Struct.Embed{}
        |> put_title("Deuterium status")
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/status")

        |> put_field("Messages learned", chan_model.trained_on)
        |> put_field("Messages contributed to the global model", chan_model.global_trained_on)
        |> put_field("Total messages in the global model", global_model.trained_on)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed]}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "stats"}} = inter, _}) do
    used_space = Deutexrium.Persistence.used_space() |> div(1024)
    used_memory = :erlang.memory(:total) |> div(1024 * 1024)
    %{guild: guild_server_cnt, channel: chan_server_cnt} = Server.Supervisor.server_count
    {uptime, _} = :erlang.statistics(:wall_clock)
    uptime = uptime |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)
    been_created_for = ((DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - (Nostrum.Cache.Me.get().id
        |> Bitwise.>>>(22) |> Kernel.+(1_420_070_400_000)))
        |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)

    embed = %Struct.Embed{}
        |> put_title("Deuterium resource usage")
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/stats")

        |> put_field("Space taken up by user data", "#{used_space} KiB (#{used_space |> div(1024)} MiB)", true)
        |> put_field("Uptime", "#{uptime}", true)
        |> put_field("Time since I was created", "#{been_created_for}", true)
        |> put_field("Known servers", "#{Deutexrium.Persistence.guild_cnt}", true)
        |> put_field("Known channels", "#{Deutexrium.Persistence.chan_cnt}", true)
        |> put_field("Used RAM", "#{used_memory} MiB", true)
        |> put_field("Internal request routers", "#{Server.Supervisor.router_cnt}", true)
        |> put_field("Internal guild servers", "#{guild_server_cnt}", true)
        |> put_field("Internal channel servers", "#{chan_server_cnt}", true)
        |> put_field("Total internal processes", "#{Process.list |> length()}", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "scoreboard"}} = inter, _}) do
    %{user_stats: scoreboard} = Server.Guild.get_meta(inter.guild_id)

    embed = %Struct.Embed{} |> put_title("Deuterium scoreboard")
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/scoreboard")
    top10 = scoreboard |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
    {_, embed} = top10 |> Enum.reduce({1, embed}, fn {k, v}, {idx, acc} ->
      {idx + 1, acc |> put_field("##{idx}", "<@#{k}> - #{v} messages")}
    end)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target, options: [%{name: property}]}]}} = inter, _}) do
    if check_admin_perm(inter) do
      cond do
        target == "server" and property == "settings" ->
          :ok = Server.Guild.reset(inter.guild_id, :settings)
        target == "channel" and property == "settings" ->
          :ok = Server.Channel.reset({inter.channel_id, inter.guild_id}, :settings)
        target == "channel" and property == "model" ->
          :ok = Server.Channel.reset({inter.channel_id, inter.guild_id}, :model)
      end
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target} #{property} reset**", flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "settings"}} = inter, _}) do
    if check_admin_perm(inter) do
      components = Server.Settings.initialize({inter.channel_id, inter.guild_id}, inter)
      Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end
  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{custom_id: "settings_target", values: [value]}} = inter, _}) do
    {_, components} = Server.Settings.switch_ctx({inter.channel_id, inter.guild_id}, case value do
      "server" -> :guild
      str -> :erlang.binary_to_integer(str)
    end)
    Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
  end
  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{component_type: 2, custom_id: id}} = inter, _}) do
    {_, components} = Server.Settings.clicked({inter.channel_id, inter.guild_id}, id)
    Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "search", options: [%{name: "word", value: word}]}} = inter, _}) do
    word = word |> String.downcase
    if check_admin_perm(inter) do
      embed = %Struct.Embed{}
          |> put_title("Search results")
          |> put_color(0xe6f916)
          |> put_url("https://deut.portasynthinca3.me/admin-cmd/search")
      embed = Server.Channel.token_stats({inter.channel_id, inter.guild_id})
          |> Enum.filter(fn
            {k, _} when is_tuple(k) or is_atom(k) -> false
            {k, _} -> k |> String.downcase |> String.contains?(word)
            end)
          |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
          |> Enum.reduce(embed, fn {k, v}, acc ->
        acc |> put_field("`#{k}`", "#{v} occurences", true)
      end)

      Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "forget", options: [%{name: "word", value: word}]}} = inter, _}) do
    if check_admin_perm(inter) do
      Server.Channel.forget({inter.channel_id, inter.guild_id}, word)
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **i forgor `#{word}` :skull:**", flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "impostor"}} = inter, _}) do
    response = if check_admin_perm(inter) do
      # delete existing webhook
      case Server.Channel.get_meta({inter.channel_id, inter.guild_id}).webhook_data do
        {id, _token} -> Api.delete_webhook(id, "removing existing webhook before adding a new one")
        _ -> :ok
      end
      # create new webhook
      case Api.create_webhook(inter.channel_id, %{name: "Deuterium impersonation mode", avatar: "https://cdn.discordapp.com/embed/avatars/0.png"}, "create webhook for impersonation") do
        {:ok, %{id: hook_id, token: hook_token}} ->
          data = {hook_id, hook_token}
          Server.Channel.set({inter.channel_id, inter.guild_id}, :webhook_data, data)
          ":white_check_mark: **impersonation activated**"
        {:error, %{status_code: 403}} ->
          ":x: **bot is missing \"Manage Webhooks\" permission**\n[More info](https://deut.portasynthinca3.me/admin-cmd/impostor)"
        {:error, err} ->
          Logger.error("error adding webhook: #{inspect err}")
          ":x: **unknown error**"
      end
    else
      @missing_privilege
    end
    Api.create_interaction_response(inter, %{type: 4, data: %{content: response, flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "export", options: [%{value: resource}, %{value: format}]}} = inter, _}) do
    format = :erlang.binary_to_atom(format)
    extension = case format do
      :etf_gz -> ".etf.gz"
      :json -> ".json"
      :bson -> ".bson"
    end
    if check_admin_perm(inter) do
      case Api.create_dm(inter.user.id) do
        {:error, _} ->
          Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **I couldnt't contact you via DMs. Check your settings**", flags: 64}})
        {:ok, %{id: dm_id}} ->
          Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **Your data package is being exported**", flags: 64}})
          case resource do
            "chan" ->
              {meta, model} = Server.Channel.export({inter.channel_id, inter.guild_id}, format)
              Api.create_message!(dm_id, %{content: ":white_check_mark: **Your data package is ready**", files: [
                %{name: "meta_#{inter.channel_id}#{extension}", body: meta},
                %{name: "model_#{inter.channel_id}#{extension}", body: model}
              ]})
            "guild" ->
              meta = Server.Guild.export(inter.guild_id, format)
              Api.create_message!(dm_id, %{content: ":white_check_mark: **Your data package is ready**", files: [
                %{name: "guild_meta_#{inter.guild_id}#{extension}", body: meta}
              ]})
          end

      end
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event(_event) do
    :ok
    # Logger.warn("unknown event: #{inspect event}")
  end

  defp check_admin_perm(inter) do
    guild = Nostrum.Cache.GuildCache.get!(inter.guild_id)
    perms = Nostrum.Struct.Guild.Member.guild_permissions(inter.member, guild)
    :administrator in perms
  end

  defp simulate_typing(text, channel, hack, guild \\ nil, username \\ nil)

  defp simulate_typing(text, channel, hack, _guild = nil, _username = nil) do
    # calculate delay
    words = text |> String.split() |> length()
    delay = floor(words * ((80 + (10 * :rand.normal())) / 60) * 1000) # 80 +/-10 wpm
      |> min(5000) # max 5s
      |> max(1000) # min 1s

    # start typing and wait
    Api.start_typing(channel)
    :timer.sleep(delay)

    # dirty hack to stop typing
    # wrong
    # it's not "dirty", it's straight up HORRIBLE
    if hack do
      case Api.create_message(channel, content: "this message will be removed shortly.... hold on") do
        {:ok, message} -> Api.delete_message(message)
        _ -> :ok
      end
    end
  end

  defp simulate_typing(text, channel, hack, guild, username) do
    # remember the current nick
    %{nick: old_nick} = Api.get_guild_member!(guild, Nostrum.Cache.Me.get().id)
    # change nickname
    Api.modify_current_user_nick(guild, %{nick: username <> " (Deuterium)"})

    # do the actual typing
    simulate_typing(text, channel, hack)

    # change nickname back
    unless old_nick != nil and String.contains?(old_nick, " (Deuterium)") do
      Api.modify_current_user_nick(guild, %{nick: old_nick})
    end
  end

  defp try_sending_webhook(data, chan, webhook, guild \\ nil)

  defp try_sending_webhook({0, _, text}, chan, _webhook, _guild) do
    # unknown user
    simulate_typing(text, chan, false)
    Api.create_message(chan, content: text)
  end

  defp try_sending_webhook({_user_id, _, text}, chan, nil, _guild) do
    # no webhook
    simulate_typing(text, chan, false)
    Api.create_message(chan, content: text)
  end

  defp try_sending_webhook({_, _, text}, chan, :fail, _guild) do
    # webhook failed, don't simulate typing
    Api.create_message(chan, content: text)
  end

  defp try_sending_webhook(what = {user_id, _, text}, chan, {id, token}, guild) do
    # get username and avatar
    {:ok, user} = Api.get_user(user_id)
    ava = "https://cdn.discordapp.com/avatars/#{user_id}/#{user.avatar}"

    # simulate tping
    simulate_typing(text, chan, true, guild, user.username)

    case Api.execute_webhook(id, token, %{content: text, username: user.username <> " (Deuterium)", avatar_url: ava}) do
      {:ok} -> :ok
      {:error, err} ->
        Logger.warn("webhook error: #{inspect err}")
        # retry with no webhook
        try_sending_webhook(what, chan, :fail)
    end
  end
end
