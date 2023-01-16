defmodule Deutexrium.Util.Webhook do
  @moduledoc """
  Helps with webhooks and typing simulation
  """

  require Logger
  alias Nostrum.Api

  def simulate_typing(text, channel, hack, guild \\ nil, username \\ nil)

  def simulate_typing(text, channel, hack, nil = _guild, nil = _username) do
    # calculate delay
    words = text |> String.split() |> length()
    delay = floor(words * ((320 + (10 * :rand.normal())) / 60) * 1000) # 320 +/-10 wpm
      |> min(5000) # max 5s
      |> max(500) # min 0.5s

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

  def simulate_typing(text, channel, hack, guild, username) do
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

  def try_sending_webhook(data, chan, webhook, guild \\ nil)

  def try_sending_webhook({text, _user_id}, chan, nil, _guild) do
    # no webhook
    simulate_typing(text, chan, false)
    Api.create_message(chan, content: text)
  end

  def try_sending_webhook({text, _user_id}, chan, :fail, _guild) do
    # webhook failed, don't simulate typing
    Api.create_message(chan, content: text)
  end

  def try_sending_webhook({text, user_id} = what, chan, {id, token}, guild) do
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
