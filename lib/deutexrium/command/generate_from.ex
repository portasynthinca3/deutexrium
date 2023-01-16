defmodule Deutexrium.Command.GenerateFrom do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates a message from the selected channel's local model
  """

  require Logger

  def spec, do: %{
    name: "generate_from",
    flags: [:defer],
    options: [
      %{
        type: 7, # channel
        name: "channel",
        required: true
      }
    ]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    text = case Server.Channel.generate({interaction.channel_id, interaction.guild_id}) do
      :error -> translate(locale, "response.generate.gen_failed")
      {text, _} -> text
    end

    Api.edit_interaction_response!(interaction, %{content: text})
  end
end
