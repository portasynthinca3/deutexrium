defmodule Deutexrium.Persistence.GuildMeta do
  @moduledoc """
  Guild data serialization
  """

  @derive Jason.Encoder
  defstruct train: true,
    global_train: false,
    autogen_rate: 20,
    impostor_rate: 100,
    enable_actions: true,
    ignore_bots: true,
    remove_mentions: false,
    max_gen_len: 10,
    user_stats: %{}

  defp path(guild_id) do
    Application.fetch_env!(:deutexrium, :data_path)
        |> Path.join("guild_meta_" <> :erlang.integer_to_binary(guild_id) <> ".etf.gz")
  end

  def load!(guild_id) when is_integer(guild_id) do
    %Deutexrium.Persistence.GuildMeta{} |> Map.merge(path(guild_id)
        |> File.read!
        |> :zlib.gunzip
        |> :erlang.binary_to_term)
  end

  def dump!(guild_id, %Deutexrium.Persistence.GuildMeta{} = data) when is_integer(guild_id) do
    data = data
        |> :erlang.term_to_binary
        |> :zlib.gzip
    File.write!(path(guild_id), data)
  end
end
