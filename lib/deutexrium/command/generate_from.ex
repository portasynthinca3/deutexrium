defmodule Deutexrium.Command.GenerateFrom do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates a message from the selected channel's local model
  """

  require Logger

  def spec, do: %{
    name: "generate_from",
    flags: [:defer],
    options: [
      %{
        type: 7, # channel
        name: "channel",
        required: true
      }
    ]
  }

  def handle_command(%Struct.Interaction{locale: locale, data: %{options: [%{name: "channel", value: target}]}} = interaction) do
    text = case Server.Channel.generate({target, interaction.guild_id}) do
      :error -> translate(locale, "response.generate.gen_failed")
      {text, _} -> text
    end

    %{content: text}
  end
end
