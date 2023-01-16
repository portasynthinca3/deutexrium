defmodule Deutexrium.Command.GenByThem do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates a message as if it was said by the selected person
  """

  require Logger

  def spec, do: %{
    name: "gen_by_them",
    flags: [:defer, {:context_menu, :user}]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    id = {interaction.channel_id, interaction.guild_id}

    case Server.Channel.generate(id, interaction.data.target_id) do
      {_text, _author} = data ->
        webhook = Server.Channel.get(id, :webhook_data)
        Api.delete_interaction_response!(interaction)
        Deutexrium.Util.Webhook.try_sending_webhook(data, interaction.channel_id, webhook, interaction.guild_id)

      :error ->
        Api.edit_interaction_response!(interaction, %{content:
          translate(locale, "response.gen_by_them.no_data", ["<@#{interaction.data.target_id}>"])})
    end
  end
end
