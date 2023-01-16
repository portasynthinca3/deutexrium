defmodule Deutexrium.Command.Support do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back contact info and channel+guild ID
  """

  def spec, do: %{
    name: "support",
    flags: [:defer, :ephemeral]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    embed = %Struct.Embed{}
      |> Struct.Embed.put_title(translate(locale, "response.support.title"))
      |> Struct.Embed.put_color(0xe6f916)
      |> Struct.Embed.put_field(translate(locale, "response.support.server"), "https://discord.gg/N52uWgD")
      |> Struct.Embed.put_field(translate(locale, "response.support.email"), "`portasynthinca3 (at) gmail.com`")
      |> Struct.Embed.put_field(translate(locale, "response.support.debug"), "`#{interaction.guild_id}, #{interaction.channel_id}`")

    Api.edit_interaction_response!(interaction, %{embeds: [embed]})
  end
end
