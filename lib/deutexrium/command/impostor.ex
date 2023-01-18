defmodule Deutexrium.Command.Impostor do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Enables impersonation in the current channel
  """

  require Logger

  def spec, do: %{
    name: "impostor",
    flags: [:defer, :ephemeral, :admin]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    # delete existing webhook
    case Server.Channel.get_meta({interaction.channel_id, interaction.guild_id}).webhook_data do
      {id, _token} -> Api.delete_webhook(id, "removing existing webhook before adding a new one")
      _ -> :ok
    end

    # create new webhook
    response = case Api.create_webhook(interaction.channel_id, %{name: "Deuterium impersonation mode", avatar: "https://cdn.discordapp.com/embed/avatars/0.png"}, "create webhook for impersonation") do
      {:ok, %{id: hook_id, token: hook_token}} ->
        data = {hook_id, hook_token}
        Server.Channel.set({interaction.channel_id, interaction.guild_id}, :webhook_data, data)
        translate(locale, "response.impostor.activated")
      {:error, %{status_code: 403}} ->
        translate(locale, "response.impostor.webhook_error")
      {:error, err} ->
        Logger.error("error adding webhook: #{inspect err}")
        translate(locale, "response.impostor.unknown_error")
    end

    %{content: response}
  end
end
