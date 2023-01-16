defmodule Deutexrium.Command.Privacy do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back the privacy policy
  """

  def spec, do: %{
    name: "privacy",
    flags: [:defer, :ephemeral]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    embed = %Struct.Embed{}
      |> Struct.Embed.put_title(translate(locale, "response.privacy.title"))
      |> Struct.Embed.put_color(0xe6f916)
      |> Struct.Embed.put_url("https://deut.portasynthinca3.me/privacy-policy")

      embed = Enum.reduce([
        "scope", "auth",
        "processing", "storage",
        "contacting", "removal",
        "disclosure",
      ], embed, fn section, embed ->
        Struct.Embed.put_field(embed,
          translate(locale, "response.privacy.#{section}.title"),
          translate(locale, "response.privacy.#{section}.paragraph"))
      end)

    Api.edit_interaction_response!(interaction, %{embeds: [embed]})
  end
end
