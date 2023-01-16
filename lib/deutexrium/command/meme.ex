defmodule Deutexrium.Command.Meme do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates and sends back a meme
  """

  def spec, do: %{
    name: "meme",
    flags: [:defer]
  }

  def handle_command(%Struct.Interaction{} = interaction) do
    file = Deutexrium.Meme.generate({interaction.channel_id, interaction.guild_id}, interaction.id)
    Api.edit_interaction_response!(interaction, %{files: [file]})
    Deutexrium.Meme.cleanup(file)
  end
end
