defmodule Deutexrium.Presence do
  use GenServer
  @moduledoc "Updates Discord presence"

  require Logger

  def init(_) do
    Process.send_after(self(), :update_presence, 5_000)
    {:ok, {}}
  end

  def handle_info(:update_presence, state) do
    Logger.debug("updating presence")
    guild_cnt = :ets.info(:nostrum_guilds) |> Keyword.get(:size)
    Nostrum.Api.update_status(:online, "#{guild_cnt} servers", 2)

    Process.send_after(self(), :update_presence, 60_000)
    {:noreply, state}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end
