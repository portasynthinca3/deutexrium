defmodule Deutexrium do
  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct
  import Nostrum.Struct.Embed
  alias Deutexrium.{ChannelServer, GuildServer}

  def binary_settings do
    [
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
  end

  def non_binary_settings do
    [
      %{value: "autogen_rate",
        name: "automatic generation rate",
        description: "automatic message generation rate (one per <value> others' messages); disabled if set to 0"}
    ]
  end

  def add_slash_commands do
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
      {"rps", "start a game of Rock-Paper-Scissors with me"}
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
          description: "setting to help with",
          required: false,
          choices: binary_settings()
              |> Enum.concat(non_binary_settings())
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
      name: "gen_from",
      description: "generate messages using the specified channel's model immediately",
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
      name: "turn",
      description: "modify binary settings",
      options: [
        %{
          name: "server",
          description: "modify a binary setting server-wise",
          type: 1, # subcommand
          options: [
            %{
              type: 3, #string
              name: "setting",
              description: "the setting to modify",
              choices: binary_settings() |> Enum.map(fn val -> Map.delete(val, :description) end),
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
              choices: binary_settings() |> Enum.map(fn val -> Map.delete(val, :description) end),
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
          description: "modify a non-binary setting server-wise",
          type: 1, # subcommand
          options: [
            %{
              type: 3, #string
              name: "setting",
              description: "the setting to modify",
              choices: non_binary_settings() |> Enum.map(fn val -> Map.delete(val, :description) end),
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
              choices: non_binary_settings() |> Enum.map(fn val -> Map.delete(val, :description) end),
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

    {:ok, _} = Api.bulk_overwrite_guild_application_commands(765604415427575828, commands)
  end



  def start_link do
    GuildServer.boot()
    ChannelServer.boot()
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _, _}) do
    add_slash_commands()
    Logger.info("ready")
  end



  def handle_event({:MESSAGE_CREATE, %Struct.Message{}=msg, _}) do
    unless msg.guild_id == nil or msg.channel_id == nil do
      GuildServer.maybe_start(msg.guild_id)
      ChannelServer.maybe_start({msg.channel_id, msg.guild_id})
      GuildServer.maybe_start(0)
      ChannelServer.maybe_start({0, 0})

      # notify users about slash commands
      if String.starts_with?(msg.content, "!!d ") do
        {:ok, _} = Api.create_message(msg.channel_id, content: ":sparkles: **The bot is now using slash commands! Try `/help`** :sparkles:")
      end

      case ChannelServer.handle_message(msg.channel_id, msg.content, msg.author.bot || false, msg.author.id) do
        :ok -> :ok
        {:message, to_send} ->
          {:ok, _} = Api.create_message(msg.channel_id, to_send)
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help", options: [%{name: "setting", value: setting}]}}=inter, _}) do
    %{name: name, description: desc} =
        binary_settings()
        |> Enum.concat(non_binary_settings())
        |> Enum.find_value(fn %{value: val}=map -> if val == setting, do: map end)

    embed = %Struct.Embed{}
        |> put_title("Deuterium setting help")
        |> put_color(0xe6f916)
        |> put_field(name, desc)
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen"}}=inter, _}) do
    GuildServer.maybe_start(inter.guild_id)
    ChannelServer.maybe_start({inter.channel_id, inter.guild_id})

    count = unless Map.has_key?(inter.data, :options) do
      1
    else
      [%{name: "count", value: val}] = inter.data.options
      val
    end

    text = 1..count
        |> Enum.map(fn _ -> ChannelServer.generate(inter.channel_id) end)
        |> Enum.join("\n")
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_from", options: [%{name: "channel", value: channel}]}}=inter, _}) do
    channel = :erlang.binary_to_integer(channel)
    GuildServer.maybe_start(inter.guild_id)
    ChannelServer.maybe_start({channel, inter.guild_id})

    text = ChannelServer.generate(channel)
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "ggen"}}=inter, _}) do
    GuildServer.maybe_start(0)
    ChannelServer.maybe_start({0, 0})

    text = ChannelServer.generate(0)
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium commands")
        |> put_color(0xe6f916)

        |> put_field("REGULAR COMMANDS", "can be run by anybody")
        |> put_field("help", ":information_source: send this message", true)
        |> put_field("help <setting>", ":information_source: show settings information", true)
        |> put_field("status", ":green_circle: show the current stats", true)
        |> put_field("stats", ":yellow_circle: show how much resources I use", true)
        |> put_field("gen <count>", ":1234: generate <count> (1 if omitted) messages using the current channel's model immediately", true)
        |> put_field("gen_from #channel", ":level_slider: immediately generate a message using the mentioned channel's model", true)
        |> put_field("ggen", ":rocket: immediately generate a message using the global model", true)
        |> put_field("donate", ":question: ways to support me", true)
        |> put_field("privacy", ":lock: my privacy policy", true)
        |> put_field("support", ":thinking: ways to get support", true)
        |> put_field("scoreboard", ":100: top-10 most active users in this server", true)
        # |> put_field("rps", ":rock: start a game of Rock-Paper-Scissors with me", true)

        |> put_field("ADMIN COMMANDS", "can only be run by those with the \"administrator\" privilege")
        |> put_field("turn server <setting> <on/off>", ":gear: turn a binary setting on or off server-wise", true)
        |> put_field("turn channel <setting> <on/off/nil>", ":gear: turn a binary setting on or off channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("set server <setting> <value>", ":gear: set a non-binary setting value server-wise", true)
        |> put_field("set channel <setting> <value/nil>", ":gear: set a non-binary setting value channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("settings <server/channel>", ":gear: show the current settings", true)
        |> put_field("reset server settings", ":rotating_light: reset server settings", true)
        |> put_field("reset channel settings", ":rotating_light: reset channel settings", true)
        |> put_field("reset channel model", ":rotating_light: reset channel message generation model", true)

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "donate"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium donations")
        |> put_color(0xe6f916)
        |> put_field(":loudspeaker: tell your friends about the bot", "...or invite it to other servers")
        |> put_field(":money_mouth: donate on Patreon", "https://patreon.com/portasynthinca3")
        |> put_field(":speaking_head: vote on DBL", "https://top.gg/bot/733605243396554813/vote")

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "privacy"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium privacy policy")
        |> put_color(0xe6f916)
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
           Deuterium does **not** store the following data:
           - Message content
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

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "support"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium support")
        |> put_color(0xe6f916)
        |> put_field(":eye: Support server", "https://discord.gg/N52uWgD")
        |> put_field(":e_mail: Email", "`portasynthinca3 (at) gmail.com`")

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "status"}}=inter, _}) do
    ChannelServer.maybe_start({inter.channel_id, inter.guild_id})
    ChannelServer.maybe_start({0, 0})
    chan_model = ChannelServer.get_model_stats(inter.channel_id)
    global_model = ChannelServer.get_model_stats(0)

    embed = %Struct.Embed{}
        |> put_title("Deuterium status")
        |> put_color(0xe6f916)

        |> put_field(":1234: Messages learned", chan_model.trained_on)
        |> put_field(":1234: Messages contributed to the global model", chan_model.global_trained_on)
        |> put_field(":1234: Total messages in the global model", global_model.trained_on)

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "stats"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium resource usage")
        |> put_color(0xe6f916)
        |> put_field("Space taken up by user data", "`#{Deutexrium.Persistence.used_space() |> div(1024*1024)} MiB`")
        |> put_field("Number of known channels", "`#{Deutexrium.Persistence.channel_cnt()}`")
        |> put_field("Number of known servers", "`#{Deutexrium.Persistence.guild_cnt()}`")

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "scoreboard"}}=inter, _}) do
    GuildServer.maybe_start(inter.guild_id)
    %{user_stats: scoreboard} = GuildServer.get_meta(inter.guild_id)

    embed = %Struct.Embed{} |> put_title("Deuterium scoreboard") |> put_color(0xe6f916)
    top10 = scoreboard |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
    {_, embed} = top10 |> Enum.reduce({1, embed}, fn {k, v}, {idx, acc} ->
      {idx + 1, acc |> put_field("##{idx}", "<@#{k}> - #{v} messages")}
    end)

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target, options: [%{name: property}]}]}}=inter, _}) do
    GuildServer.maybe_start(inter.guild_id)
    ChannelServer.maybe_start({inter.channel_id, inter.guild_id})
    cond do
      target == "server" and property == "settings" ->
        :ok = GuildServer.reset(inter.guild_id, :settings)
      target == "channel" and property == "settings" ->
        :ok = ChannelServer.reset(inter.channel_id, :settings)
      target == "channel" and property == "model" ->
        :ok = ChannelServer.reset(inter.channel_id, :model)
    end
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target} #{property} reset**", flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "turn", options: [%{name: target, options: [%{value: setting}, %{value: value}]}]}}=inter, _}) do
    GuildServer.maybe_start(inter.guild_id)
    ChannelServer.maybe_start({inter.channel_id, inter.guild_id})

    setting = :erlang.binary_to_existing_atom(setting, :utf8)
    value = case value do
      "on" -> true
      "off" -> false
      "nil" -> nil
    end
    case target do
      "server" -> GuildServer.set(inter.guild_id, setting, value)
      "channel" -> ChannelServer.set(inter.channel_id, setting, value)
    end
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target}'s `#{setting}` set to `#{setting_prettify(value)}`**", flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "set", options: [%{name: target, options: [%{value: setting}, %{value: value}]}]}}=inter, _}) do
    GuildServer.maybe_start(inter.guild_id)
    ChannelServer.maybe_start({inter.channel_id, inter.guild_id})

    setting = :erlang.binary_to_existing_atom(setting, :utf8)
    value = case setting do
      :autogen_rate -> :erlang.binary_to_integer(value)
    end
    case target do
      "server" -> GuildServer.set(inter.guild_id, setting, value)
      "channel" -> ChannelServer.set(inter.channel_id, setting, value)
    end
    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **#{target}'s `#{setting}` set to `#{setting_prettify(value)}`**", flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "settings", options: [%{name: target}]}}=inter, _}) do
    meta = case target do
      "server" ->
        GuildServer.maybe_start(inter.guild_id)
        GuildServer.get_meta(inter.guild_id)
      "channel" ->
        ChannelServer.maybe_start({inter.channel_id, inter.guild_id})
        ChannelServer.get_meta(inter.channel_id)
    end

    embed = %Struct.Embed{}
        |> put_title("Deuterium #{target} settings")
        |> put_color(0xe6f916)
    embed = Enum.reduce(Enum.concat(binary_settings(), non_binary_settings()), embed, fn elm, acc ->
      acc |> put_field(elm.name, setting_prettify(Map.get(meta, :erlang.binary_to_existing_atom(elm.value, :utf8))), true)
    end)

    {:ok} = Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event(event) do
    Logger.warn("missed event")
    IO.inspect(event)
  end

  defp setting_prettify(val) do
    case val do
      nil -> ":o: **nil**"
      true -> ":white_check_mark: **on**"
      false -> ":x: **off**"
      val when is_number(val) -> ":1234: **#{val}**"
      val when is_binary(val) -> ":record_button: **#{val}**"
    end
  end
end
