defmodule Deutexrium.Command.GenGlobal do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates a message using the global model
  """

  require Logger

  def spec, do: %{
    name: "gen_global",
    flags: [:defer],
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    text = case Server.Channel.generate({0, 0}) do
      :error -> translate(locale, "response.generate.gen_failed")
      {text, _} -> text
    end
    %{content: text}
  end
end
