defmodule Deutexrium.Translation do
  use GenServer
  require Logger
  @moduledoc """
  The server reads localization JSONs and keeps them in a table. Other functions
  use the table to localize strings.
  """

  @fallback_lang "en-US"

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, [init_args], name: __MODULE__)
  end

  defp populate_keys(json, table, lang, prefix \\ "")
  defp populate_keys("", _, lang, prefix), do:
    Logger.warn("empty key \"#{String.slice(prefix, 1..-1)}\" in \"#{lang}\"")
  defp populate_keys(json, table, lang, prefix) when is_binary(json), do:
    :ets.insert(table, {{lang, String.slice(prefix, 1..-1)}, json})
  defp populate_keys(json, table, lang, prefix) when is_map(json), do:
    for {key, value} <- json, do:
      populate_keys(value, table, lang, "#{prefix}.#{key}")

  def init(_args) do
    table = :ets.new(:translation_keys, [:named_table, :public, :set])
    reload_langs(table)
    {:ok, table}
  end

  defp reload_langs(table) do
    :ets.delete_all_objects(table)
    tr_root = Path.join(:code.priv_dir(:deutexrium), "translation")

    langs = for file_path <- Path.wildcard(Path.join(tr_root, "*.json")) do
      lang = file_path |> Path.basename |> Path.rootname
      File.read!(file_path)
        |> Jason.decode!
        |> populate_keys(table, lang)
      lang
    end

    :ets.insert(table, {:languages, langs})
    Logger.info("reloaded #{length(langs)} locales")
  end

  def handle_call(:reload, _from, table) do
    reload_langs(table)
    {:reply, :ok, table}
  end

  # PUBLIC INTERFACE

  def reload(), do: GenServer.call(__MODULE__, :reload)

  def translate(lang, key) do
    case :ets.lookup(:translation_keys, {lang, key}) do
      [{_, val}] -> val
      [] ->
        if lang == @fallback_lang do
          Logger.error("no translation for \"#{key}\" in \"#{lang}\" (@fallback_lang)")
          key
        else
          Logger.warn("no translation for \"#{key}\" in \"#{lang}\"")
          translate(@fallback_lang, key)
        end
    end
  end

  def translate(lang, key, replace) do
    source = translate(lang, key)
    Enum.with_index(replace)
      |> Enum.reduce(source, fn {replacement, index}, string ->
        String.replace(string, "$#{index + 1}", replacement)
      end)
  end

  def list_languages do
    [{_, langs}] = :ets.lookup(:translation_keys, :languages)
    langs
  end

  def translate_to_all(key) do
    for lang <- list_languages() do
      {lang, translate(lang, key)}
    end |> Enum.into(%{})
  end
end
