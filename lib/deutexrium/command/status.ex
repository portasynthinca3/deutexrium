defmodule Deutexrium.Command.Status do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back the model status
  """

  def spec, do: %{
    name: "status",
    flags: [:defer]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    chan_meta = Server.Channel.get_meta({interaction.channel_id, interaction.guild_id})
    global_meta = Server.Channel.get_meta({0, 0})

    embed = %Struct.Embed{}
        |> Struct.Embed.put_title(translate(locale, "response.status.title"))
        |> Struct.Embed.put_color(0xe6f916)
        |> Struct.Embed.put_url("https://deut.psi3.ru/commands/status")

        |> Struct.Embed.put_field(translate(locale, "response.status.this_chan"), chan_meta.total_msgs)
        |> Struct.Embed.put_field(translate(locale, "response.status.global"), chan_meta.global_trained_on)
        |> Struct.Embed.put_field(translate(locale, "response.status.global_total"), global_meta.total_msgs)

    %{embeds: [embed]}
  end
end
