defmodule Deutexrium.Command.PreTrain do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Trains the current channel model on existing messages
  """

  require Logger

  def spec, do: %{
    name: "pre_train",
    flags: [:defer, :ephemeral, :admin],
    options: [
      %{
        type: 4, # integer
        name: "count",
        required: true
      }
    ]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    count = case interaction.data.options do
      nil -> 1000
      [%{name: "count", value: val}] -> val
    end

    if count <= 10_000 do
      Server.Channel.start_pre_train({interaction.channel_id, interaction.guild_id}, interaction, count, locale)
    else
      Api.edit_interaction_response!(interaction, %{content: translate(locale, "response.pre_train.error.too_much")})
    end
  end
end
