defmodule Deutexrium.Command.Settings do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Invokes the settings menu
  """

  def spec, do: %{
    name: "settings",
    flags: [:defer, :ephemeral, :admin]
  }

  def handle_command(%Struct.Interaction{} = interaction) do
    {content, components} = Server.Settings.initialize(interaction)
    Api.edit_interaction_response!(interaction, %{content: content, components: components})
  end

  def handle_other({:INTERACTION_CREATE, %Struct.Interaction{data: %{custom_id: "settings_target", values: [value]}} = inter, _}) do
    {_old_inter, {content, components}} = Server.Settings.switch_ctx(inter, case value do
      "server" -> :guild
      str -> :erlang.binary_to_integer(str)
    end)
    Api.create_interaction_response!(inter, %{type: 7, data: %{content: content, components: components, flags: 64}})
  end
  def handle_other({:INTERACTION_CREATE, %Struct.Interaction{data: %{component_type: t, custom_id: id}} = inter, _}) when t == 2 or t == 8 do
    {_old_inter, {content, components}} = Server.Settings.clicked(inter, id)
    Api.create_interaction_response!(inter, %{type: 7, data: %{content: content, components: components, flags: 64}})
  end

  def handle_other(_), do: :ok
end
