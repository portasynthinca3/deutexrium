defmodule Deutexrium.Persistence do
  @moduledoc """
  Serialization umbrella functions
  """

  def used_space do
    path = Application.fetch_env!(:deutexrium, :data_path)
    File.ls!(path) |> Enum.reduce(0, fn file, acc ->
      acc + File.stat!(Path.join(path, file)).size
    end)
  end

  def channel_cnt do
    path = Application.fetch_env!(:deutexrium, :data_path)
    length(File.ls!(path) |> Enum.filter(fn x -> String.starts_with?(x, "model_") end))
  end

  def guild_cnt do
    path = Application.fetch_env!(:deutexrium, :data_path)
    length(File.ls!(path) |> Enum.filter(fn x -> String.starts_with?(x, "guild_") end))
  end
end
