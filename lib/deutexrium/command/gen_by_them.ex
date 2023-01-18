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
        {:delete_and_finish, {data, interaction.channel_id, webhook, interaction.guild_id}}

      :error ->
        %{content: translate(locale, "response.gen_by_them.no_data", ["<@#{interaction.data.target_id}>"])}
    end
  end

  def finish_handling({data, channel_id, webhook, guild_id}) do
    Deutexrium.Util.Webhook.try_sending_webhook(data, channel_id, webhook, guild_id)
  end
end
