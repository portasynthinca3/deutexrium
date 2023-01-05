defmodule Deutexrium.Persistence.Meta do
  @moduledoc """
  Channel metadata serialization
  """

  alias Deutexrium.Persistence

  @type channel_setting()
    :: :train
     | :global_train
     | :autogen_rate
     | :impostor_rate
     | :enable_actions
     | :ignore_bots
     | :remove_mentions
     | :max_gen_len
     | :total_msgs
     | :webhook_data

  defstruct train: nil,
    global_train: nil,
    autogen_rate: nil,
    impostor_rate: nil,
    enable_actions: nil,
    ignore_bots: nil,
    remove_mentions: nil,
    max_gen_len: nil,
    # system data
    total_msgs: 0,
    global_trained_on: 0,
    webhook_data: nil,
    last_message: nil

  defp path(channel_id), do: Persistence.root_for(channel_id) |> Path.join("meta.etf.gz")

  def load!(channel_id) when is_integer(channel_id) do
    %Deutexrium.Persistence.Meta{} |> Map.merge(path(channel_id)
        |> File.read!
        |> :zlib.gunzip
        |> :erlang.binary_to_term)
  end

  def dump!(channel_id, %Deutexrium.Persistence.Meta{} = data) when is_integer(channel_id) do
    data = data
        |> :erlang.term_to_binary
        |> :zlib.gzip
    File.write(path(channel_id), data)
  end
end
