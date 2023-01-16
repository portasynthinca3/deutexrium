{git_hash, _} = System.cmd("git", ["rev-parse", "HEAD"])
git_hash = String.trim(git_hash) |> String.slice(0..5)

{_, dirty} = System.cmd("git", ["diff-files", "--quiet"])
dirty = dirty > 0
git_hash = if dirty do "#{git_hash}-dirty" else git_hash end

defmodule Deutexrium.Command.Stats do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Sends back UNINTERESTING and BORING info
  """

  @app_version Mix.Project.config[:version]
  @git_hash git_hash

  def spec, do: %{
    name: "stats",
    flags: [:defer, :ephemeral, :dm]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    used_space = GenServer.call(Deutexrium.Persistence, :storage_size) |> div(1024)
    used_memory = :erlang.memory(:total) |> div(1024 * 1024)
    %{guild: guild_server_cnt, channel: chan_server_cnt} = Server.RqRouter.server_count
    {uptime, _} = :erlang.statistics(:wall_clock)
    uptime = uptime |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)
    been_created_for = ((DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - (Nostrum.Cache.Me.get().id
        |> Bitwise.>>>(22) |> Kernel.+(1_420_070_400_000)))
        |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)

    embed = %Struct.Embed{}
        |> Struct.Embed.put_title(translate(locale, "response.stats.title"))
        |> Struct.Embed.put_color(0xe6f916)
        |> Struct.Embed.put_url("https://deut.portasynthinca3.me/commands/stats")

        |> Struct.Embed.put_field(translate(locale, "response.stats.data_size.title"),
          translate(locale, "response.stats.data_size.value", ["#{used_space}", "#{used_space |> div(1024)}"]), true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.uptime"), "#{uptime}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.existence"), "#{been_created_for}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.servers"), "#{Deutexrium.Persistence.guild_cnt}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.channels"), "#{Deutexrium.Persistence.chan_cnt}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.ram.title"), translate(locale, "response.stats.ram.value", ["#{used_memory}"]), true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.guild_servers"), "#{guild_server_cnt}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.channel_servers"), "#{chan_server_cnt}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.processes"), "#{Process.list |> length()}", true)
        |> Struct.Embed.put_field(translate(locale, "response.stats.version"), "#{@app_version} `#{@git_hash}`", true)

    Api.edit_interaction_response!(interaction, %{embeds: [embed], flags: 64})
  end
end
