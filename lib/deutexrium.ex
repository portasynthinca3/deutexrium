defmodule Deutexrium do
  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct
  import Nostrum.Struct.Embed

  def binary_settings do
    [
      %{value: "collect",
        name: "message collection",
        description: "train the channel-specific message generation model"},
      %{value: "gcollect",
        name: "global message collection",
        description: "thain the global message generation model shared across all channels and servers"},
      %{value: "bot_ignoration",
        name: "bot ignoration",
        description: "ignore other bot's messages"},
      %{value: "remove_mentions",
        name: "mention removal",
        description: "remove mentions in generated messages (doesn't affect messages generated using the global model)"}
    ]
  end

  def non_binary_settings do
    [
      %{value: "autorate",
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

    # no-param commands
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
      %{
        name: title,
        description: desc
      }
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
        }
      ]
    } | commands]

    {:ok, _} = Api.bulk_overwrite_guild_application_commands(765604415427575828, commands)
  end

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _, _}) do
    Logger.info("ready")
    add_slash_commands()
  end

  def handle_event({:MESSAGE_CREATE, %Struct.Message{}=msg, _}) do
    :ok
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
      Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed]}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "help"}}=inter, _}) do
    embed = %Struct.Embed{}
        |> put_title("Deuterium commands")
        |> put_color(0xe6f916)

        |> put_field("REGULAR COMMANDS", "can be run by anybody")
        |> put_field("help", ":information_source: send this message", true)
        |> put_field("help <setting>", ":information_source: show setting information", true)
        |> put_field("status", ":green_circle: show the current settings and stats", true)
        |> put_field("stats", ":yellow_circle: show how much resources I use", true)
        |> put_field("gen <count>", ":1234: generate <count> (1 if omitted) messages using the current channel's model immediately", true)
        |> put_field("gen_from #channel", ":level_slider: immediately generate a message using the mentioned channel's model", true)
        |> put_field("ggen", ":rocket: immediately generate a message using the global model", true)
        |> put_field("donate", ":question: ways to support me", true)
        |> put_field("privacy", ":lock: my privacy policy", true)
        |> put_field("support", ":thinking: ways to get support", true)
        |> put_field("scoreboard", ":100: top-10 most active users in this server", true)
        |> put_field("rps", ":rock: start a game of Rock-Paper-Scissors with me", true)

        |> put_field("ADMIN COMMANDS", "can only be run by those with the \"administrator\" privilege")
        |> put_field("turn server <setting> <on/off>", ":gear: turn a binary setting on or off server-wise", true)
        |> put_field("turn channel <setting> <on/off/nil>", ":gear: turn a binary setting on or off channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("set server <setting> <value>", ":gear: set a non-binary setting value server-wise", true)
        |> put_field("set channel <setting> <value/nil>", ":gear: set a non-binary setting value channel-wise, or make it use the server-wide value (nil)", true)
        |> put_field("reset server settings", ":rotating_light: reset server settings", true)
        |> put_field("reset channel settings", ":rotating_light: reset channel settings", true)
        |> put_field("reset channel model", ":rotating_light: reset channel message generation model", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed]}})
  end

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target, options: [%{name: property}]}]}}=inter, _}) do

    Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **" <> target <> " " <> property <> " reset**"}})
  end

  def handle_event(_event) do
    :noop
  end
end
