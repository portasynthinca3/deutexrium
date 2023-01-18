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
    {:finish, %{files: [file]}, file}
  end

  def finish_handling(file) do
    Deutexrium.Meme.cleanup(file)
  end
end
