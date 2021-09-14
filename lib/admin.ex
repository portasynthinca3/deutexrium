defmodule Admin do
  def dump(shutdown \\ false) do
    # dump all data
    :ets.match(:channel_servers, :'$1') |> Enum.each(fn [{id, _}] ->
      Deutexrium.ChannelServer.shutdown(id, shutdown)
    end)
    :ets.match(:guild_servers, :'$1') |> Enum.each(fn [{id, _}] ->
      Deutexrium.GuildServer.shutdown(id, shutdown)
    end)
  end

  def shutdown do
    dump(true)
    Deutexrium.Sup.stop()
  end
end
