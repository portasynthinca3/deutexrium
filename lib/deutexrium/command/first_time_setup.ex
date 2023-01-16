defmodule Deutexrium.Command.FirstTimeSetup do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Invokes the first time setup process
  """

  def spec, do: %{
    name: "first_time_setup",
    flags: [:defer, :ephemeral, :admin]
  }

  def handle_command(%Struct.Interaction{} = interaction) do
    {content, components} = Server.Settings.initialize(interaction)
    Api.edit_interaction_response!(interaction, %{content: content, components: components})
  end
end
