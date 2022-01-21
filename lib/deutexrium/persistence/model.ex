require Protocol
Protocol.derive(Jason.Encoder, Markov)

defmodule Deutexrium.Persistence.Model do
  require Logger
  alias Deutexrium.Persistence.Model

  @derive Jason.Encoder
  defstruct data: %Markov{sanitize_tokens: true, shift: true},
    trained_on: 0, global_trained_on: 0,
    messages: [], forget_operations: []

  defp path(channel_id) do
    Application.fetch_env!(:deutexrium, :data_path)
        |> Path.join("model_" <> :erlang.integer_to_binary(channel_id) <> ".etf.gz")
  end

  def load!(channel_id) when is_integer(channel_id) do
    model = %Model{} |> Map.merge(path(channel_id)
        |> File.read!
        |> :zlib.gunzip
        |> :erlang.binary_to_term)
    model |> Map.merge(%{data: model.data
        |> Map.merge(%{shift: true})})
  end

  def dump!(channel_id, %Model{}=data) when is_integer(channel_id) do
    data = data
        |> :erlang.term_to_binary
        |> :zlib.gzip
    File.write!(path(channel_id), data)
  end
end
