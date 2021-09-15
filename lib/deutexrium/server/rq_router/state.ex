defmodule Deutexrium.Server.RqRouter.State do
  defstruct guild_pids: %{},
            channel_pids: %{},
            ref_receivers: %{},
            shut_down: false
end
