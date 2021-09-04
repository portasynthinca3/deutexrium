defmodule Deutexrium.Persistence.Meta do
  defstruct train: nil,
    global_train: nil,
    autogen_rate: nil,
    total_msgs: 0,
    next_gen_milestone: 20,
    enable_actions: nil,
    ignore_bots: nil,
    remove_mentions: nil

  defp path(channel_id) do
    Application.fetch_env!(:deutexrium, :data_path)
        |> Path.join("meta_" <> :erlang.integer_to_binary(channel_id) <> ".etf.gz")
  end

  def load!(channel_id) when is_integer(channel_id) do
    path(channel_id)
        |> File.read!
        |> :zlib.gunzip
        |> :erlang.binary_to_term
  end

  def dump!(channel_id, %Deutexrium.Persistence.Meta{}=data) when is_integer(channel_id) do
    data = data
        |> :erlang.term_to_binary
        |> :zlib.gzip
    File.write!(path(channel_id), data)
  end
end
