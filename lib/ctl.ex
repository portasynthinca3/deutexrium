defmodule Ctl do
  @moduledoc """
  Admin functions meant to be executed from the shell
  """

  alias Nostrum.Api

  def shutdown do
    Deutexrium.Server.Supervisor.shutdown
  end

  def dump_model(channel) do
    Deutexrium.Persistence.Model.load!(channel)
  end

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
          choices: Deutexrium.binary_settings
              |> Enum.concat(Deutexrium.non_binary_settings)
              |> Enum.concat(Deutexrium.command_help)
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
      name: "join",
      description: "joins a voice channel",
      options: [
        %{
          type: 7, # channel
          name: "channel",
          description: "the channel to join",
          required: true
        },
        %{
          type: 3, # string
          name: "language",
          description: "your spoken language",
          required: true,
          choices: [
            %{value: "en", name: "English"},
            %{value: "ru", name: "Russian"},
          ]
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
              choices: Deutexrium.binary_settings
                  |> Enum.map(fn val -> Map.delete(val, :description) end),
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
              choices: Deutexrium.binary_settings
                  |> Enum.map(fn val -> Map.delete(val, :description) end),
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
              choices: Deutexrium.non_binary_settings
                  |> Enum.map(fn val -> Map.delete(val, :description) end),
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
              choices: Deutexrium.non_binary_settings
                  |> Enum.map(fn val -> Map.delete(val, :description) end),
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

    commands = [%{
      name: "export",
      description: "export data",
      options: [
        %{
          type: 3, # string
          name: "resource",
          description: "resource to export",
          required: true,
          choices: [
            %{value: "chan", name: "channel model and settings"},
            %{value: "guild", name: "server settings"}
          ],
        },
        %{
          type: 3, # string
          name: "format",
          description: "encoding format",
          required: true,
          choices: [
            %{value: "etf_gz", name: "etf.gz"},
            # TODO: doesn't work.
            # %{value: "json", name: "json"},
            # %{value: "bson", name: "bson"}
          ],
        }
      ]
    } | commands]

    {:ok, _} = if guild == 0 do
      Api.bulk_overwrite_global_application_commands(commands)
    else
      Api.bulk_overwrite_guild_application_commands(guild, commands)
    end
  end
end
