defmodule Deutexrium do
  @moduledoc """
  Accepts data from Nostrum and invokes Channel, Guild and Voice servers'
  functions accordingly.
  """

  @version Mix.Project.config[:version]

  use Nostrum.Consumer
  require Logger
  alias Nostrum.Api
  alias Nostrum.Struct
  import Nostrum.Struct.Embed
  alias Deutexrium.Server
  import Deutexrium.Translation, only: [translate: 2, translate: 3]

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _, _}) do
    Logger.info("ready!")
  end



  def handle_event({:MESSAGE_CREATE, %Struct.Message{} = msg, _}) do
    self = msg.author.id == Nostrum.Cache.Me.get().id
    unless self or msg.guild_id == nil or msg.channel_id == nil or byte_size(msg.content) == 0 do
      # react to mentions and replies
      bot_id = Nostrum.Cache.Me.get().id
      reference = Map.get(msg, :referenced_message, nil)
      ref_author = if reference, do: reference.author.id, else: nil
      ref_app = if reference, do: reference.application_id, else: nil
      bot_mentioned = String.contains?(msg.content, ["<@#{bot_id}>", "<@!#{bot_id}>"])
        or ref_author == bot_id
        or ref_app == bot_id

      if bot_mentioned do
        prompt = msg.content |> String.replace("<@#{bot_id}>", "") |> String.replace("<@!#{bot_id}>", "")
        Logger.debug("mentioned")
        {text, _} = Server.Channel.generate({msg.channel_id, msg.guild_id}, nil, prompt)
        simulate_typing(text, msg.channel_id, false)
        Api.create_message(msg.channel_id, content: text, message_reference: %{message_id: msg.id})
      else
        # only train if it doesn't contain bot mentions
        case Server.Channel.handle_message({msg.channel_id, msg.guild_id}, msg.content, msg.author.bot || false, msg.author.id) do
          :ok -> :ok
          {:message, {text, author}} ->
            # see it it's impostor time
            impostor_rate = Server.Channel.get({msg.channel_id, msg.guild_id}, :impostor_rate)
            impostor_rate = if impostor_rate == nil, do: 0, else: impostor_rate
            webhook_data = if impostor_rate > 0 and :rand.uniform() <= impostor_rate / 100.0 do
                Server.Channel.get_meta({msg.channel_id, msg.guild_id}).webhook_data
            else
              nil
            end
            try_sending_webhook({text, author}, msg.channel_id, webhook_data, msg.guild_id)
        end
      end
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "generate"}} = inter, _}) do
    id = {inter.channel_id, inter.guild_id}
    count = if inter.data.options == nil do
      1
    else
      [%{name: "count", value: val}] = inter.data.options
      if val in 1..Server.Channel.get(id, :max_gen_len) do val else 0 end
    end

    if count > 0 do
      sentences = for _ <- 1..count, do: elem(Server.Channel.generate(id), 0)
      if :error in sentences do
        Logger.error("generation failed")
        Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.generate.gen_failed")}})
      else
        Api.create_interaction_response(inter, %{type: 4, data: %{content: Enum.join(sentences, " ")}})
      end
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.generate.val_too_big"), flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_by_them", target_id: user_id}} = inter, _}) do
    id = {inter.channel_id, inter.guild_id}
    case Server.Channel.generate(id, user_id) do
      {_text, _author} = data ->
        webhook = Server.Channel.get(id, :webhook_data)
        Api.create_interaction_response(inter, %{type: 4, data: %{content: case webhook do
          {_, _} -> translate(inter.locale, "response.gen_by_them.normal")
          nil -> translate(inter.locale, "response.gen_by_them.no_impostor")
        end, flags: 64}})
        try_sending_webhook(data, inter.channel_id, webhook, inter.guild_id)

      :error ->
        Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.gen_by_them.no_data", ["<@#{user_id}>"]), flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "generate_from", options: [%{name: "channel", value: channel}]}} = inter, _}) do
    text = case Server.Channel.generate({channel, inter.guild_id}) do
      :error -> translate(inter.locale, "response.generate.gen_failed")
      {text, _} -> text
    end
    Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "gen_global"}} = inter, _}) do
    {text, _} = Server.Channel.generate({0, 0})
    Api.create_interaction_response(inter, %{type: 4, data: %{content: text}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "help"}} = inter, _}) do
    embed = %Struct.Embed{}
      |> put_title(translate(locale, "response.help.header"))
      |> put_color(0xe6f916)
      |> put_description(translate(locale, "response.help.sub"))
      |> put_url("https://deut.portasynthinca3.me/")

      |> put_field(translate(locale, "response.help.regular"), translate(locale, "response.help.regular_sub"))

    embed = Enum.reduce([
        "help", "status",
        "stats", "generate",
        "generate_from", "gen_global",
        "donate", "privacy",
        "support", "scoreboard"
      ], embed, fn command, embed ->
        put_field(embed, translate(locale, "command.#{command}.title"), translate(locale, "response.help.#{command}"), true)
      end)

    embed = embed
      |> put_field(translate(locale, "response.help.admin"), translate(locale, "response.help.admin_sub"))
      |> put_field(translate(locale, "command.settings.title"), translate(locale, "response.help.settings"), true)
      |> put_field(translate(locale, "command.impostor.title"), translate(locale, "response.help.impostor"), true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "donate"}} = inter, _}) do
    embed = %Struct.Embed{}
      |> put_title(translate(locale, "response.donate.title"))
      |> put_color(0xe6f916)

      |> put_field(translate(locale, "response.donate.share"), translate(locale, "response.donate.invite"))
      |> put_field(translate(locale, "response.donate.patreon"), "https://patreon.com/portasynthinca3")
      |> put_field(translate(locale, "response.donate.paypal"), "https://paypal.me/portasynthinca3")
      |> put_field(translate(locale, "response.donate.dbl"), "https://top.gg/bot/733605243396554813/vote")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "privacy"}} = inter, _}) do
    embed = %Struct.Embed{}
      |> put_title(translate(locale, "response.privacy.title"))
      |> put_color(0xe6f916)
      |> put_url("https://deut.portasynthinca3.me/privacy-policy")

      embed = Enum.reduce([
        "scope", "auth",
        "processing", "storage",
        "contacting", "removal",
        "disclosure",
      ], embed, fn section, embed ->
        put_field(embed, translate(locale, "response.privacy.#{section}.title"), translate(locale, "response.privacy.#{section}.paragraph"))
      end)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "support"}} = inter, _}) do
    embed = %Struct.Embed{}
        |> put_title(translate(locale, "response.support.title"))
        |> put_color(0xe6f916)
        |> put_field(translate(locale, "response.support.server"), "https://discord.gg/N52uWgD")
        |> put_field(translate(locale, "response.support.email"), "`portasynthinca3 (at) gmail.com`")
        |> put_field(translate(locale, "response.support.debug"), "`#{inter.guild_id}, #{inter.channel_id}`")

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "status"}} = inter, _}) do
    chan_meta = Server.Channel.get_meta({inter.channel_id, inter.guild_id})
    global_meta = Server.Channel.get_meta({0, 0})

    embed = %Struct.Embed{}
        |> put_title(translate(locale, "response.status.title"))
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/status")

        |> put_field(translate(locale, "response.status.this_chan"), chan_meta.total_msgs)
        |> put_field(translate(locale, "response.status.global"), chan_meta.global_trained_on)
        |> put_field(translate(locale, "response.status.global_total"), global_meta.total_msgs)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed]}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{locale: locale, data: %{name: "stats"}} = inter, _}) do
    used_space = GenServer.call(Deutexrium.Persistence, :storage_size) |> div(1024)
    used_memory = :erlang.memory(:total) |> div(1024 * 1024)
    %{guild: guild_server_cnt, channel: chan_server_cnt} = Server.RqRouter.server_count
    {uptime, _} = :erlang.statistics(:wall_clock)
    uptime = uptime |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)
    been_created_for = ((DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - (Nostrum.Cache.Me.get().id
        |> Bitwise.>>>(22) |> Kernel.+(1_420_070_400_000)))
        |> Timex.Duration.from_milliseconds |> Timex.Format.Duration.Formatter.format(:humanized)

    embed = %Struct.Embed{}
        |> put_title(translate(locale, "response.stats.title"))
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/stats")

        |> put_field(translate(locale, "response.stats.data_size.title"),
          translate(locale, "response.stats.data_size.value", ["#{used_space}", "#{used_space |> div(1024)}"]), true)
        |> put_field(translate(locale, "response.stats.uptime"), "#{uptime}", true)
        |> put_field(translate(locale, "response.stats.existence"), "#{been_created_for}", true)
        |> put_field(translate(locale, "response.stats.servers"), "#{Deutexrium.Persistence.guild_cnt}", true)
        |> put_field(translate(locale, "response.stats.channels"), "#{Deutexrium.Persistence.chan_cnt}", true)
        |> put_field(translate(locale, "response.stats.ram.title"), translate(locale, "response.stats.ram.value", ["#{used_memory}"]), true)
        |> put_field(translate(locale, "response.stats.guild_servers"), "#{guild_server_cnt}", true)
        |> put_field(translate(locale, "response.stats.channel_servers"), "#{chan_server_cnt}", true)
        |> put_field(translate(locale, "response.stats.processes"), "#{Process.list |> length()}", true)
        |> put_field(translate(locale, "response.stats.version"), "#{@version}", true)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "scoreboard"}} = inter, _}) do
    %{user_stats: scoreboard} = Server.Guild.get_meta(inter.guild_id)

    embed = %Struct.Embed{} |> put_title(translate(inter.locale, "response.scoreboard.title"))
        |> put_color(0xe6f916)
        |> put_url("https://deut.portasynthinca3.me/commands/scoreboard")
    top10 = scoreboard |> Enum.sort_by(fn {_, v} -> v end) |> Enum.reverse |> Enum.slice(0..9)
    {_, embed} = top10 |> Enum.reduce({1, embed}, fn {k, v}, {idx, acc} ->
      {idx + 1, acc |> put_field("##{idx}", translate(inter.locale, "response.scoreboard.row", ["<@#{k}>", "#{v}"]))}
    end)

    Api.create_interaction_response(inter, %{type: 4, data: %{embeds: [embed], flags: 64}})
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "reset", options: [%{name: target}]}} = inter, _}) do
    if check_admin_perm(inter) do
      :ok = case target do
        "server" -> Server.Guild.reset(inter.guild_id, :settings)
        "settings" -> Server.Channel.reset({inter.channel_id, inter.guild_id}, :settings)
        "model" -> Server.Channel.reset({inter.channel_id, inter.guild_id}, :model)
      end
      Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.reset.#{target}"), flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.missing_admin"), flags: 64}})
    end
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "settings"}} = inter, _}) do
    if check_admin_perm(inter) do
      components = Server.Settings.initialize(inter)
      Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
    else
      Api.create_interaction_response(inter, %{type: 4, data: %{content: translate(inter.locale, "response.missing_admin"), flags: 64}})
    end
  end
  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{custom_id: "settings_target", values: [value]}} = inter, _}) do
    {old_inter, components} = Server.Settings.switch_ctx(inter, case value do
      "server" -> :guild
      str -> :erlang.binary_to_integer(str)
    end)
    Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
    Api.delete_interaction_response!(old_inter)
  end
  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{component_type: 2, custom_id: id}} = inter, _}) do
    {old_inter, components} = Server.Settings.clicked(inter, id)
    Api.create_interaction_response!(inter, %{type: 4, data: %{components: components, flags: 64}})
    Api.delete_interaction_response!(old_inter)
  end



  def handle_event({:INTERACTION_CREATE, %Struct.Interaction{data: %{name: "impostor"}} = inter, _}) do
    Api.create_interaction_response(inter, %{type: 5, data: %{flags: 64}})

    response = if check_admin_perm(inter) do
      # delete existing webhook
      case Server.Channel.get_meta({inter.channel_id, inter.guild_id}).webhook_data do
        {id, _token} -> Api.delete_webhook(id, "removing existing webhook before adding a new one")
        _ -> :ok
      end
      # create new webhook
      case Api.create_webhook(inter.channel_id, %{name: "Deuterium impersonation mode", avatar: "https://cdn.discordapp.com/embed/avatars/0.png"}, "create webhook for impersonation") do
        {:ok, %{id: hook_id, token: hook_token}} ->
          data = {hook_id, hook_token}
          Server.Channel.set({inter.channel_id, inter.guild_id}, :webhook_data, data)
          translate(inter.locale, "response.impostor.activated")
        {:error, %{status_code: 403}} ->
          translate(inter.locale, "response.impostor.webhook_error")
        {:error, err} ->
          Logger.error("error adding webhook: #{inspect err}")
          translate(inter.locale, "response.unknown_error")
      end
    else
      translate(inter.locale, "response.missing_admin")
    end

    Api.edit_interaction_response!(inter, %{content: response})
  end



  def handle_event(_event) do
    :ok
    # Logger.warn("unknown event: #{inspect event}")
  end

  defp check_admin_perm(inter) do
    guild = Nostrum.Cache.GuildCache.get!(inter.guild_id)
    perms = Nostrum.Struct.Guild.Member.guild_permissions(inter.member, guild)
    :administrator in perms
  end

  defp simulate_typing(text, channel, hack, guild \\ nil, username \\ nil)

  defp simulate_typing(text, channel, hack, nil = _guild, nil = _username) do
    # calculate delay
    words = text |> String.split() |> length()
    delay = floor(words * ((160 + (10 * :rand.normal())) / 60) * 1000) # 16 +/-10 wpm
      |> min(5000) # max 5s
      |> max(1000) # min 1s

    # start typing and wait
    Api.start_typing(channel)
    :timer.sleep(delay)

    # dirty hack to stop typing
    # wrong
    # it's not "dirty", it's straight up HORRIBLE
    if hack do
      case Api.create_message(channel, content: "this message will be removed shortly.... hold on") do
        {:ok, message} -> Api.delete_message(message)
        _ -> :ok
      end
    end
  end

  defp simulate_typing(text, channel, hack, guild, username) do
    # remember the current nick
    %{nick: old_nick} = Api.get_guild_member!(guild, Nostrum.Cache.Me.get().id)
    # change nickname
    Api.modify_current_user_nick(guild, %{nick: username <> " (Deuterium)"})

    # do the actual typing
    simulate_typing(text, channel, hack)

    # change nickname back
    unless old_nick != nil and String.contains?(old_nick, " (Deuterium)") do
      Api.modify_current_user_nick(guild, %{nick: old_nick})
    end
  end

  defp try_sending_webhook(data, chan, webhook, guild \\ nil)

  defp try_sending_webhook({text, _user_id}, chan, nil, _guild) do
    # no webhook
    simulate_typing(text, chan, false)
    Api.create_message(chan, content: text)
  end

  defp try_sending_webhook({text, _user_id}, chan, :fail, _guild) do
    # webhook failed, don't simulate typing
    Api.create_message(chan, content: text)
  end

  defp try_sending_webhook({text, user_id} = what, chan, {id, token}, guild) do
    # get username and avatar
    {:ok, user} = Api.get_user(user_id)
    ava = "https://cdn.discordapp.com/avatars/#{user_id}/#{user.avatar}"

    # simulate tping
    simulate_typing(text, chan, true, guild, user.username)

    case Api.execute_webhook(id, token, %{content: text, username: user.username <> " (Deuterium)", avatar_url: ava}) do
      {:ok} -> :ok
      {:error, err} ->
        Logger.warn("webhook error: #{inspect err}")
        # retry with no webhook
        try_sending_webhook(what, chan, :fail)
    end
  end
end
