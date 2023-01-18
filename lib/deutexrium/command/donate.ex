defmodule Deutexrium.Command.Donate do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back donation info
  """

  def spec, do: %{
    name: "donate",
    flags: [:defer, :ephemeral]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    embed = %Struct.Embed{}
      |> Struct.Embed.put_title(translate(locale, "response.donate.title"))
      |> Struct.Embed.put_color(0xe6f916)

      |> Struct.Embed.put_field(translate(locale, "response.donate.share"), translate(locale, "response.donate.invite"))
      |> Struct.Embed.put_field(translate(locale, "response.donate.patreon"), "https://patreon.com/portasynthinca3")
      |> Struct.Embed.put_field(translate(locale, "response.donate.paypal"), "https://paypal.me/portasynthinca3")
      |> Struct.Embed.put_field(translate(locale, "response.donate.dbl"), "https://top.gg/bot/733605243396554813/vote")

    %{embeds: [embed]}
  end
end
