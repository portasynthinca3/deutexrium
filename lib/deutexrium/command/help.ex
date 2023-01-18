defmodule Deutexrium.Command.Help do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back command descriptions in an embed
  """

  def spec, do: %{
    name: "help",
    flags: [:defer, :ephemeral]
  }

  def handle_command(%Struct.Interaction{locale: locale, data: %{name: "help"}} = interaction) do
    embed = %Struct.Embed{}
      |> Struct.Embed.put_title(translate(locale, "response.help.header"))
      |> Struct.Embed.put_color(0xe6f916)
      |> Struct.Embed.put_description(translate(locale, "response.help.sub"))
      |> Struct.Embed.put_url("https://deut.portasynthinca3.me/")
      |> Struct.Embed.put_field(translate(locale, "response.help.regular"), translate(locale, "response.help.regular_sub"))

    commands = Deutexrium.CommandHolder.list_commands()
      |> Enum.map(fn {_, mod, _} -> mod.spec() end)
    regular = Enum.filter(commands, fn %{flags: flags} -> :admin not in flags end)
    admin = Enum.filter(commands, fn %{flags: flags} -> :admin in flags end)

    embed = Enum.reduce(regular, embed, fn %{name: name}, embed ->
      Struct.Embed.put_field(embed, translate(locale, "command.#{name}.title"), translate(locale, "response.help.#{name}"), true)
    end)
      |> Struct.Embed.put_field(translate(locale, "response.help.admin"), translate(locale, "response.help.admin_sub"))

    embed = Enum.reduce(admin, embed, fn %{name: name}, embed ->
      Struct.Embed.put_field(embed, translate(locale, "command.#{name}.title"), translate(locale, "response.help.#{name}"), true)
    end)

    %{embeds: [embed]}
  end
end
