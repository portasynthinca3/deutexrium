defmodule Admin do
  def dump do
    # dump all data
    :ets.match(:channel_servers, :'$1') |> Enum.each(fn [{id, _}] ->
      Deutexrium.ChannelServer.shutdown(id, true)
    end)
    :ets.match(:guild_servers, :'$1') |> Enum.each(fn [{id, _}] ->
      Deutexrium.GuildServer.shutdown(id, true)
    end)
  end

  def shutdown do
    dump()
    Deutexrium.Sup.stop()
  end
end
