defmodule Deutexrium do
  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct
  import Nostrum.Struct.Embed
  alias Deutexrium.Server

  @binary_settings [
    %{value: "train",
      name: "message collection",
      description: "train the channel-specific message generation model"},
    %{value: "global_train",
      name: "global message collection",
      description: "thain the global message generation model shared across all channels and servers"},
    %{value: "ignore_bots",
      name: "bot ignoration",
      description: "ignore other bot's messages"},
    %{value: "remove_mentions",
      name: "mention removal",
      description: "remove mentions in generated messages (doesn't affect messages generated using the global model)"}
  ]

  @non_binary_settings [
    %{value: "autogen_rate",
      name: "automatic generation rate",
      description: "automatic message generation rate (one per <value> others' messages); disabled if set to 0"},
    %{value: "max_gen_len",
      name: "maximum /gen option value",
      description: "maximum number of messages to generate by one batch using the /gen command"}
  ]

  @command_help [
  ]

  @missing_privilege ":x: **missing \"administrator\" privilege**\n[More info](https://deut.yamka.app/admin-cmd/admin-commands-notice)"

  def add_slash_commands(guild \\ 0) do
    commands = []

    commands = [%{
      name: "reset",
      description: "reset the generation model or settings of this channel or server",
      options: [
        %{
          name: "channel",
          description: "reset the generation model or settings of this channel",
          type: 2, # subcommand group
          options: [
            %{
              name: "model",
              description: "reset the generation model of this channel",
              type: 1 # subcommand
            },
            %{
              name: "settings",
              description: "reset the settings of this channel",
              type: 1 # subcommand
            }
          ]
        },
        %{
          name: "server",
          description: "reset the settings of this server",
          type: 2, # subcommand group
          options: [
            %{
              name: "settings",
              description: "reset the settings of this server",
              type: 1 # subcommand
            }
          ]
        }
      ]
    } | commands]

    # zero-parameter commands
    no_param = [
      {"status", "show the current settings and stats"},
      {"stats", "show how much resources I use"},
      {"ggen", "immediately generate a message using the global model"},
      {"donate", "ways to support the bot"},
      {"privacy", "privacy policy"},
      {"support", "ways to get support"},
      {"scoreboard", "top-10 most active users in this server"},
      {"rps", "start a game of Rock-Paper-Scissors with me"},
      {"impostor", "enable impersonation mode. Please read /help impostor before using this command!"}
    ]
    no_param = no_param |> Enum.map(fn {title, desc} ->
      %{name: title, description: desc}
    end)
    commands = commands ++ no_param

    commands = [%{
      name: "help",
      description: "show help",
      options: [
        %{
          type: 3, # string
          name: "setting",
          description: "setting or command to help with",
          required: false,
          choices: @binary_settings
              |> Enum.concat(@non_binary_settings)
              |> Enum.concat(@command_help)
              |> Enum.map(fn val -> Map.delete(val, :description) end),
        }
      ]
    } | commands]

    commands = [%{
      name: "gen",
      description: "generate messages using the current channel's model immediately",
      options: [
        %{
          type: 4, # integer
          name: "count",
          description: "the number of messages to generate; defaults to 1",
          required: false
        }
      ]
    } | commands]

    commands = [%{
      name: "gen_by",
      description: "generate messages using the current channel's model with a specific sentiment and author",
      options: [
        %{
          type: 6, # user
          name: "user",
          description: "the user to mimic",
          required: false
        },
        %{
          type: 3, # string
          name: "sentiment",
          description: "the sentiment to produce",
          required: false,
          choices: [
            %{value: "strongly_positive", name: "strongly positive"},
            %{value: "positive", name: "positive"},
            %{value: "neutral", name: "neutral"},
            %{value: "negative", name: "negative"},
            %{value: "strongly_negative", name: "strongly negative"}
          ],
        }
      ]
    } | commands]

    commands = [%{
      name: "gen_from",
      description: "generate a message using the specified channel's model immediately",
      options: [
        %{
          type: 7, # channel
          name: "channel",
          description: "the channel to use",
          required: true
        }
      ]
    } | commands]

    commands = [%{
      name: "search",
      description: "search for a word in the model",
      options: [
        %{
          type: 3, # string
          name: "word",
          description: "the word to search for",
          required: true
        }
      ]
    } | commands]

    commands = [%{
      name: "forget",
      description: "forget a word",
      options: [
        %{
          type: 3, #wordstring
          name: "word",
          description: "the exact word to forget",
          required: true
        }
      ]
    } | commands]

    commands = [%{
      name: "turn",
      description: "modify binary settings",
      options: [
        %{
          name: "server",
          description: "modify a binary setting server-wide",
          type: 1, # subcommand
          options: [
            %{
              type: 3, #string
              name: "setting",
              description: "the setting to modify",
              choices: @binary_settings |> Enum.map(fn val -> Map.delete(val, :description) end),
              required: true
            },
            %{
              type: 3, # string
              name: "value",
              description: "the value to assign",
              choices: [
                %{value: "on", name: "on"},
                %{value: "off", name: "off"}
              ],
              required: true
            }
          ]
        },
        %{
          name: "channel",
          description: "modify a binary setting channel-wise",
          type: 1, # subcommand
          options: [
            %{
              type: 3, #string
              name: "setting",
              description: "the setting to modify",
              choices: @binary_settings |> Enum.map(fn val -> Map.delete(val, :description) end),
              required: true
            },
            %{
              type: 3, # string
              name: "value",
              description: "the value to assign",
              choices: [
                %{value: "on", name: "on"},
                %{value: "off", name: "off"},
                %{value: "nil", name: "nil"}
              ],
              required: true
            }
          ]
        }
      ]
    } | commands]

    commands = [%{
      name: "set",
      description: "modify non-binary settings",
      options: [
        %{
          name: "server",
          description: "modify a non-binary setting server-wide",
          type: 1, # subcommand
          options: [
            %{
              type: 3, #string
              name: "setting",
              description: "the setting to modify",
              choices: @non_binary_settings |> Enum.map(fn val -> Map.delete(val, :description) end),
              required: true
            },
            %{
              type: 3, # string
              name: "value",
              description: "the value to assign",
              required: true
            }
          ]
        },
        %{
          name: "channel",
          description: "modify a non-binary setting channel-wise",
          type: 1, # subcommand
          options: [
            %{
              type: 3, # string
              name: "setting",
              description: "the setting to modify",
              choices: @non_binary_settings |> Enum.map(fn val -> Map.delete(val, :description) end),
              required: true
            },
            %{
              type: 3, # string
              name: "value",
              description: "the value to assign",
              required: true
            }
          ]
        }
      ]
    } | commands]

    commands = [%{
      name: "settings",
      description: "display settings values",
      options: [
        %{
          name: "server",
          description: "display server settings",
          type: 1, # subcommand
        },
        %{
          name: "channel",
          description: "display channel settings",
          type: 1, # subcommand
        }
      ]
    } | commands]

    {:ok, _} = if guild == 0 do
      Api.bulk_overwrite_global_application_commands(commands)
    else
      Api.bulk_overwrite_guild_application_commands(guild, commands)
    end
  end

  def update_presence do
    Logger.info("updating presence")
    guild_cnt = Nostrum.Cache.GuildCache.all() |> Enum.count()
    chan_cnt = Deutexrium.Persistence.channel_cnt()
    Api.update_status("", "#{guild_cnt} servers and #{chan_cnt} channels", 2)
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
    Logger.info("ready")
  end



  def handle_event({:MESSAGE_CREATE, %Struct.Message{}=msg, _}) do
    unless msg.guild_id == nil or msg.channel_id == nil do
      # notify users about slash commands
      if String.starts_with?(msg.content, "!!d ") do
        Api.create_message(msg.channel_id, content: """
        :sparkles: **I am now using slash commands! Try `/help`** :sparkles:
        If /help doesn't work, please kick me and re-authorize using this link:
        https://discord.com/oauth2/authorize?client_id=733605243396554813&scope=bot%20applications.commands
        _(this message will never stop appearing)_
        """)
      end

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
        Logger.debug("mentioned with sentiment=#{inspect sent}, responding with same")
        case Server.Channel.generate({msg.channel_id, msg.guild_id}, sent) do
          {_, _, text} ->
            simulate_typing(text, msg.channel_id)
            Api.create_message(msg.channel_id, content: text, message_reference: %{message_id: msg.id})
          :error -> :ok
        end
      else
        # only train if it doesn't contain bot mentions
        meta = Server.Channel.get_meta({msg.channel_id, msg.guild_id})
        case Server.Channel.handle_message({msg.channel_id, msg.guild_id}, msg.content, msg.author.bot || false, msg.author.id) do
          :ok -> :ok
          {:message, text} ->
            try_sending_webhook(text, msg.channel_id, meta.webhook_data)
        end
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help", options: [%{name: "setting", value: setting}]}}=inter, _}) do
    %{name: name, description: desc} =
        @binary_settings
        |> Enum.concat(@non_binary_settings)
        |> Enum.concat(@command_help)
        |> Enum.find_value(fn %{value: val}=map -> if val == setting, do: map end)

    embed = %Struct.Embed{}
        |> put_title("Deuterium setting/command help")
        |> put_color(0xe6f916)
        |> put_field(name, desc)
    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen"}}=inter, _}) do
    unless inter_notice(inter) do
      id = {inter.channel_id, inter.guild_id}
      count = if inter.data.options == nil do
        1
      else
        [%{name: "count", value: val}] = inter.data.options
        if val in 1..Server.Channel.get(id, :max_gen_len) do val else 0 end
      end

      unless count == 0 do
        text = 1..count
            |> Enum.map(fn _ -> {_, _, t} = Server.Channel.generate(id)
                        t end)
            |> Enum.join("\n")
        Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
      else
        Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **value too big**\n[More info](https://deut.yamka.app/commands/gen-less-than-number-greater-than)", flags: 64}})
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_by", options: nil}}=inter, _}) do
    unless inter_notice(inter) do
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **you must supply the sentiment, author or both. For simple generation use [/gen](https://deut.yamka.app/commands/gen)**", flags: 64}})
    end
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_by", options: options}=data}=inter, _}) do
    unless inter_notice(inter) do
      id = {inter.channel_id, inter.guild_id}
      {sentiment, user} = case options do
        [%{name: "user", value: u}, %{name: "sentiment", value: s}] -> {s, u}
        [%{name: "sentiment", value: s}, %{name: "user", value: u}] -> {s, u}
        [%{name: "sentiment", value: s}] -> {s, nil}
        [%{name: "user", value: u}] -> {"neutral", u}
      end
      sentiment = :erlang.binary_to_existing_atom(sentiment)
      user = unless user == nil, do: :erlang.binary_to_integer(user)

      case Server.Channel.generate(id, sentiment, user) do
        {_, _, _} = result ->
          webhook = Server.Channel.get(id, :webhook_data)
          Api.create_interaction_response(inter, %{type: 4, data: %{content: case webhook do
            {_, _} -> ":white_check_mark: **the response will be sent shortly**"
            nil -> ":question: **the response will be sent as a normal message shortly. Try [/impostor](https://deut.yamka.app/commands/impostor)**"
          end, flags: 64}})
          try_sending_webhook(result, inter.channel_id, webhook)

        :error ->
          Api.create_interaction_response(inter, %{type: 4, data: %{content: cond do
            user != nil -> ":x: **I haven't heard anything `#{Sentiment.name(sentiment)}` from <@#{user}>**"
            user == nil -> ":x: **I haven't heard anything `#{Sentiment.name(sentiment)}`**"
          end, flags: 64}})
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_from", options: [%{name: "channel", value: channel}]}}=inter, _}) do
    unless inter_notice(inter) do
      channel = :erlang.binary_to_integer(channel)
      {_, _, text} = Server.Channel.generate({channel, inter.guild_id})
      Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "ggen"}}=inter, _}) do
    {_, _, text} = Server.Channel.generate({0, 0})
    Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium commands")
        |> put_color(0xe6f916)
        |> put_description("More extensive help information at https://deut.yamka.app/")
        |> put_url("https://deut.yamka.app/")

        |> put_field(":loudspeaker: ANNOUNCEMENT", "A bug was recently found in how message generation models were trained that led to poor output quality if authorship and/or sentiment tracking were used. As a result, I have completely wiped all generation models. In addition, I'm now saving raw message content along with Markov models so this this never happens again and I'm able to re-train them in case a bug like this pops up. This means that the privacy policy had to be updated. If you object to the changes, please either stop using the bot or reach out to me if you'd like to opt-out or suggest an alternative solution. The bot is open source so you can [take a look at its code](https://github.com/portasynthinca3/deutexrium) and evaluate how it uses your data.")

        |> put_field("REGULAR COMMANDS", "can be run by anybody")
        |> put_field("help", ":information_source: send this message", true)
        |> put_field("help <setting>", ":information_source: show settings information", true)
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
        # |> put_field("rps", ":rock: start a game of Rock-Paper-Scissors with me", true)

        |> put_field("ADMIN COMMANDS", "can only be run by those with the \"administrator\" privilege")
        |> put_field("turn server <setting> <on/off>", ":gear: turn a binary setting on or off server-wide", true)
        |> put_field("turn channel <setting> <on/off/nil>", ":gear: turn a binary setting on or off channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("set server <setting> <value>", ":gear: set a non-binary setting value server-wide", true)
        |> put_field("set channel <setting> <value/nil>", ":gear: set a non-binary setting value channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("settings <server/channel>", ":gear: show the current settings", true)
        |> put_field("reset server settings", ":rotating_light: reset server settings", true)
        |> put_field("reset channel settings", ":rotating_light: reset channel settings", true)
        |> put_field("reset channel model", ":rotating_light: reset channel message generation model", true)
        |> put_field("search <word>", ":mag: search for a word in the model", true)
        |> put_field("forget <word>", ":skull: forget a specific word", true)
        |> put_field("impostor", "<:amogus:887939317371138048> enable impersonation mode. **please read /help impostor before using**", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "donate"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Ways to support Deuterium")
        |> put_color(0xe6f916)

        |> put_field(":loudspeaker: tell your friends about the bot", "...or invite it to other servers")
        |> put_field(":money_mouth: donate on Patreon", "https://patreon.com/portasynthinca3")
        |> put_field(":money_mouth: donate via PayPal", "https://paypal.me/portasynthinca3")
        |> put_field(":speaking_head: vote on DBL", "https://top.gg/bot/733605243396554813/vote")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "privacy"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium privacy policy")
        |> put_color(0xe6f916)
        |> put_url("https://deut.yamka.app/privacy-policy")

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

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "support"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium support")
        |> put_color(0xe6f916)
        |> put_field(":eye: Support server", "https://discord.gg/N52uWgD")
        |> put_field(":e_mail: Email", "`portasynthinca3 (at) gmail.com`")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "status"}}=inter, _}) do
    unless inter_notice(inter) do
      chan_model = Server.Channel.get_model_stats({inter.channel_id, inter.guild_id})
      global_model = Server.Channel.get_model_stats({0, 0})

      embed = %Struct.Embed{}
          |> put_title("Deuterium status")
          |> put_color(0xe6f916)
          |> put_url("https://deut.yamka.app/commands/status")

          |> put_field("Messages learned", chan_model.trained_on)
          |> put_field("Messages contributed to the global model", chan_model.global_trained_on)
          |> put_field("Total messages in the global model", global_model.trained_on)

      Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed]}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "stats"}}=inter, _}) do
    used_space = Deutexrium.Persistence.used_space() |> div(1024)
    used_memory = :erlang.memory(:total) |> div(1024 * 1024)
    %{guilds: guild_server_cnt, channels: chan_server_cnt} = Server.Supervisor.server_count
    {uptime, _} = :erlang.statistics(:wall_clock)
    uptime = uptime |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)
    been_created_for = ((DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - (Nostrum.Cache.Me.get().id
        |> Bitwise.>>>(22) |> Kernel.+(1420070400000)))
        |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)

    embed = %Struct.Embed{}
        |> put_title("Deuterium resource usage")
        |> put_color(0xe6f916)
        |> put_url("https://deut.yamka.app/commands/stats")

        |> put_field("Space taken up by user data", "#{used_space} KiB (#{used_space |> div(1024)} MiB)", true)
        |> put_field("Bot uptime", "#{uptime}", true)
        |> put_field("Time since I was created", "#{been_created_for}", true)
        |> put_field("Number of known channels", "#{Deutexrium.Persistence.channel_cnt}", true)
        |> put_field("Number of known servers", "#{Deutexrium.Persistence.guild_cnt}", true)
        |> put_field("Used RAM", "#{used_memory} MiB", true)
        |> put_field("Internal request routers", "#{Server.Supervisor.router_cnt}", true)
        |> put_field("Internal guild servers", "#{guild_server_cnt}", true)
        |> put_field("Internal channel servers", "#{chan_server_cnt}", true)
        |> put_field("Total internal processes", "#{Process.list |> length()}", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "scoreboard"}}=inter, _}) do
    unless inter_notice(inter) do
      %{user_stats: scoreboard} = Server.Guild.get_meta(inter.guild_id)

      embed = %Struct.Embed{} |> put_title("Deuterium scoreboard")
          |> put_color(0xe6f916)
          |> put_url("https://deut.yamka.app/commands/scoreboard")
      top10 = scoreboard |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
      {_, embed} = top10 |> Enum.reduce({1, embed}, fn {k, v}, {idx, acc} ->
        {idx + 1, acc |> put_field("##{idx}", "<@#{k}> - #{v} messages")}
      end)

      Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target, options: [%{name: property}]}]}}=inter, _}) do
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



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "turn", options: [%{name: target, options: [%{value: setting}, %{value: value}]}]}}=inter, _}) do
    if check_admin_perm(inter) do
      setting = :erlang.binary_to_existing_atom(setting, :utf8)
      value = case value do
        "on" -> true
        "off" -> false
        "nil" -> nil
      end
      case target do
        "server" -> Server.Guild.set(inter.guild_id, setting, value)
        "channel" -> Server.Channel.set({inter.channel_id, inter.guild_id}, setting, value)
      end
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target}'s `#{setting}` set to** #{setting_prettify(value)}", flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "set", options: [%{name: target, options: [%{value: setting}, %{value: value}]}]}}=inter, _}) do
    if check_admin_perm(inter) do
      setting = :erlang.binary_to_existing_atom(setting, :utf8)
      value = case setting do
        # parse numeric values
        numeric when numeric in [:autogen_rate, :max_gen_len] ->
          try do
            :erlang.binary_to_integer(value)
          rescue _ -> 0 end
      end
      case target do
        "server" -> Server.Guild.set(inter.guild_id, setting, value)
        "channel" -> Server.Channel.set({inter.channel_id, inter.guild_id}, setting, value)
      end
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target}'s `#{setting}` set to #{setting_prettify(value)}**", flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "settings", options: [%{name: target}]}}=inter, _}) do
    if check_admin_perm(inter) do
      meta = case target do
        "server" ->
          Server.Guild.get_meta(inter.guild_id) |> Map.delete(:webhook_data)
        "channel" ->
          Server.Channel.get_meta({inter.channel_id, inter.guild_id})
      end

      embed = %Struct.Embed{}
          |> put_title("Deuterium #{target} settings")
          |> put_color(0xe6f916)
          |> put_url("https://deut.yamka.app/admin-cmd/settings")
      embed = Enum.reduce(Enum.concat(@binary_settings, @non_binary_settings), embed, fn elm, acc ->
        acc |> put_field(elm.name, setting_prettify(Map.get(meta, :erlang.binary_to_existing_atom(elm.value, :utf8))), true)
      end)

      Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "search", options: [%{name: "word", value: word}]}}=inter, _}) do
    word = word |> String.downcase
    if check_admin_perm(inter) do
      embed = %Struct.Embed{}
          |> put_title("Search results")
          |> put_color(0xe6f916)
          |> put_url("https://deut.yamka.app/admin-cmd/search")
      embed = Server.Channel.token_stats({inter.channel_id, inter.guild_id})
          |> Enum.filter(fn
            {k, _} when is_atom(k) -> false
            {k, _} when is_integer(k) -> false
            {k, _} ->
              k |> String.downcase |> String.contains?(word)
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



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "forget", options: [%{name: "word", value: word}]}}=inter, _}) do
    if check_admin_perm(inter) do
      Server.Channel.forget({inter.channel_id, inter.guild_id}, word)
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **i forgor `#{word}` :skull:**", flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: @missing_privilege, flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "impostor"}}=inter, _}) do
    response = if check_admin_perm(inter) do
      # delete existing webhook
      case Server.Channel.get_meta({inter.channel_id, inter.guild_id}).webhook_data do
        {id, _token} -> Api.delete_webhook(id, "removing existing webhook before adding a new one")
        _ -> :ok
      end
      # create new webhook
      case Api.create_webhook(inter.channel_id, %{name: "Deuterium", avatar: "https://cdn.discordapp.com/embed/avatars/0.png"}, "create webhook for impersonation") do
        {:ok, %{id: hook_id, token: hook_token}} ->
          data = {hook_id, hook_token}
          Server.Channel.set({inter.channel_id, inter.guild_id}, :webhook_data, data)
          ":white_check_mark: **impersonation activated**"
        {:error, %{status_code: 403}} ->
          ":x: **bot is missing \"Manage Webhooks\" permission**\n[More info](https://deut.yamka.app/admin-cmd/impostor)"
        {:error, err} ->
          Logger.error("error adding webhook: #{inspect err}")
          ":x: **unknown error**"
      end
    else
      @missing_privilege
    end
    Api.create_interaction_response(inter, %{type: 4, data: %{content: response, flags: 64}})
  end

  def handle_event(_event) do
    :noop
  end



  defp setting_prettify(val) do
    case val do
      nil -> ":o: **nil**"
      true -> ":white_check_mark: **on**"
      false -> ":x: **off**"
      val -> "#{val}"
    end
  end

  defp check_admin_perm(inter) do
    guild = Nostrum.Cache.GuildCache.get!(inter.guild_id)
    perms = Nostrum.Struct.Guild.Member.guild_permissions(inter.member, guild)
    :administrator in perms
  end

  defp inter_notice(inter) do
    invalid = inter.guild_id == nil
    if invalid do
      Logger.warn("interaction in #{inter.channel_id} has guild_id=nil")
      Api.create_interaction_response(inter, %{type: 4, data: %{content: ":x: **I don't have slash command permissions. Please kick me and re-authorize using this link: https://discord.com/oauth2/authorize?client_id=733605243396554813&scope=bot%20applications.commands**", flags: 64}})
      true
    else
      false
    end
  end

  defp simulate_typing(text, channel) do
    words = text |> String.split() |> length()
    delay = floor(words * ((40 + (10 * :rand.normal())) / 60) * 1000) # 40 +/-10 wpm
    Api.start_typing(channel)
    :timer.sleep(delay)
  end

  defp try_sending_webhook({0, _, text}, chan, _) do
    Api.create_message(chan, content: text)
  end
  defp try_sending_webhook({_, _, text}, chan, :nil) do
    Api.create_message(chan, content: text)
  end
  defp try_sending_webhook({user_id, _, text}=what, chan, {id, token}) do
    {:ok, user} = Api.get_user(user_id)
    ava = "https://cdn.discordapp.com/avatars/#{user_id}/#{user.avatar}"
    case Api.execute_webhook(id, token, %{content: text, username: user.username <> " (Deuterium)", avatar_url: ava}) do
      {:ok} -> :ok
      {:error, err} ->
        Logger.warn("webhook error: #{err}")
        try_sending_webhook(what, chan, :nil)
    end
  end
end
