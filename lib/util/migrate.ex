defmodule Deutexrium.Util.Migrate do
  @moduledoc "Migrates Deuterium v1 models to v2"

  require Logger
  alias Deutexrium.Persistence

  def migrate(channel_id, limit \\ 100000) do
    Logger.info("migrate-#{channel_id}: starting")
    data_path = Application.fetch_env!(:deutexrium, :data_path)

    # read model and meta
    Logger.debug("migrate-#{channel_id}: reading model and meta")
    try do
      old_model = Path.join([data_path, "archive", "model_#{channel_id}.etf.gz"])
        |> File.read! |> :zlib.gunzip |> :erlang.binary_to_term
      old_meta = Path.join([data_path, "archive", "meta_#{channel_id}.etf.gz"])
        |> File.read! |> :zlib.gunzip |> :erlang.binary_to_term
      Logger.debug("migrate-#{channel_id}: read model and meta")

      # create new model
      File.rm_rf(Persistence.root_for(channel_id))
      {:ok, new_model} = Markov.load(Persistence.root_for(channel_id), [
        sanitize_tokens: true,
        order: 3,
        shift_probabilities: true,
        store_log: [
          :train, :gen,
          :start, :end
        ],
      ])

      # train new model on messages
      Logger.debug("migrate-#{channel_id}: training")
      {last, cnt} = old_model.messages
        |> Enum.reverse
        |> Enum.slice(0 .. limit - 1)
        |> Enum.reduce({nil, 0}, fn {author, message}, {last, cnt} ->
          Markov.Prompt.train(new_model, "#{author} #{message}", last, [{:author, author}])
          if rem(cnt, 1000) == 0, do:
            Logger.info("migrate-#{channel_id}: #{cnt} processed")
          {last, cnt + 1}
        end)

      Logger.info("migrate-#{channel_id}: #{cnt} processed")

      # new meta
      Logger.debug("migrate-#{channel_id}: transforming meta")
      new_meta = old_meta
        |> Map.put(:total_msgs, cnt)
        |> Map.put(:global_trained_on, 0)
        |> Map.put(:last_message, last)

      # save data
      new_meta_bin = :erlang.term_to_binary(new_meta) |> :zlib.gzip
      File.write!(Path.join(Persistence.root_for(channel_id), "meta.etf.gz"), new_meta_bin)
      :ok = Markov.unload(new_model)

      Logger.info("migrate-#{channel_id}: complete")
      File.rm(Path.join([data_path, "archive", "model_#{channel_id}.etf.gz"]))
      File.rm(Path.join([data_path, "archive", "meta_#{channel_id}.etf.gz"]))
      :ok
    rescue
      _ -> Logger.warn("migrate-#{channel_id}: failed to convert")
    end
  end

  def migrate_all do
    Logger.info("migrate all: starting")

    path = Application.fetch_env!(:deutexrium, :data_path)
    model_ids = Path.join(path, "archive")
      |> File.ls!
      |> Enum.filter(fn x -> String.starts_with?(x, "model_") end)
      |> Enum.map(fn x ->
        {number, _} = x
          |> String.slice(String.length("model_")..-1)
          |> Integer.parse
        number
      end)
      |> Enum.sort

    Logger.info("migrate all: #{length(model_ids)} models to convert")

    Flow.from_enumerable(model_ids)
      |> Flow.map(&migrate/1)
      |> Flow.run

    Logger.info("migrate all: #{length(model_ids)} models migrated")
  end
end


# root = "/var/deutexrium/data"
# File.ls!("/var/deutexrium/data")
#   |> Enum.flat_map(fn dir -> Path.join(root, dir) |> File.ls! |> Enum.map(fn sub -> Path.join([root, dir, sub, "state.etf"]) end) end)
#   |> Enum.map(fn path -> {path, %{
#     __struct__: Markov.ModelServer.State,
#     main_table: nil,
#     history_file: nil,
#     path: nil,
#     options: [sanitize_tokens: true, order: 3, shift_probabilities: true, store_log: [:train, :gen, :start, :end]]}
#   } end)
#   |> Enum.map(fn {path, state} -> File.write!(path, state |> :erlang.term_to_binary) end)
