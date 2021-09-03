defmodule Deutexrium do
  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct

  def add_slash_commands do
    # add commands
    {:ok, _} = Api.create_guild_application_command(765604415427575828, %{
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
    })
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

  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target, options: [%{name: property}]}]}}=inter, _}) do

    Api.create_interaction_response(inter, %{type: 4, data: %{content: ":white_check_mark: **" <> target <> " " <> property <> " reset**"}})
  end

  def handle_event(_event) do
    :noop
  end
end
