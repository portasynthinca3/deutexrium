defmodule Deutexrium.Command.Reset do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Resets the channel model or channel/server settings
  """

  def spec, do: %{
    name: "reset",
    flags: [:defer, :ephemeral, :admin],
    options: [
      %{type: 1, name: "model"},
      %{type: 1, name: "settings"},
      %{type: 1, name: "server"}
    ]
  }

  def handle_command(%Struct.Interaction{locale: locale, data: %{options: [%{name: target}]}} = interaction) do
    :ok = case target do
      "server" -> Server.Guild.reset(interaction.guild_id, :settings)
      "settings" -> Server.Channel.reset({interaction.channel_id, interaction.guild_id}, :settings)
      "model" -> Server.Channel.reset({interaction.channel_id, interaction.guild_id}, :model)
    end
    %{content: translate(locale, "response.reset.#{target}")}
  end
end
