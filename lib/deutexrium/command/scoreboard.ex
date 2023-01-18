defmodule Deutexrium.Command.Scoreboard do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back the server scoreboard
  """

  def spec, do: %{
    name: "scoreboard",
    flags: [:defer, :ephemeral]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    %{user_stats: scoreboard} = Server.Guild.get_meta(interaction.guild_id)

    embed = %Struct.Embed{}
        |> Struct.Embed.put_title(translate(locale, "response.scoreboard.title"))
        |> Struct.Embed.put_color(0xe6f916)
        |> Struct.Embed.put_url("https://deut.portasynthinca3.me/commands/scoreboard")
    top10 = scoreboard |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
    {_, embed} = top10 |> Enum.reduce({1, embed}, fn {k, v}, {idx, acc} ->
      {idx + 1, acc |> Struct.Embed.put_field("##{idx}", translate(locale, "response.scoreboard.row", ["<@#{k}>", "#{v}"]))}
    end)

    %{embeds: [embed]}
  end
end
