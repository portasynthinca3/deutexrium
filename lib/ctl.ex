defmodule Ctl do
  @moduledoc """
  Admin functions meant to be executed from the shell
  """

  alias Nostrum.Api

  def shutdown do
    Deutexrium.Server.RqRouter.shutdown
  end

  def dump_model(channel) do
    Deutexrium.Persistence.Model.load!(channel)
  end

  def unload(resource) do
    GenServer.cast({:via, Registry, {Registry.Server, resource}}, {:shutdown, false})
  end

  def add_slash_commands(guild \\ 0) do
    commands = []

    # reset
    commands = [%{
      name: "reset",
      description: "reset something",
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
      {"status", "key statistics"},
      {"stats", "my resource usage. this isn't particularly interesting"},
      {"ggen", "immediately generate a message using the global model"},
      {"donate", "ways to support me"},
      {"privacy", "privacy policy"},
      {"support", "ways to get support"},
      {"scoreboard", "top-10 most active users on this server"},
      {"impostor", "enable impersonation mode"},
      {"settings", "configure settings"},
      {"help", "show help"},
    ]
    no_param = no_param |> Enum.map(fn {title, desc} ->
      %{name: title, description: desc}
    end)
    commands = commands ++ no_param

    # gen
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

    # gen_by
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

    # gen_from
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

    # join
    commands = [%{
      name: "join",
      description: "joins a voice channel",
      options: [
        %{
          type: 7, # channel
          name: "channel",
          description: "the channel to join",
          channel_types: [2], # guild voice
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

    # search
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

    # forget
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

    # export
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

    # Generate by them
    commands = [%{
      name: "Generate message by them",
      type: 2
    } | commands]

    result = if guild == 0 do
      Api.bulk_overwrite_global_application_commands(commands)
    else
      Api.bulk_overwrite_guild_application_commands(guild, commands)
    end

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
