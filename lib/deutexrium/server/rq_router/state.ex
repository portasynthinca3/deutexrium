defmodule Deutexrium.Server.RqRouter.State do
  defstruct guild_pids: %{},
            channel_pids: %{},
            ref_receivers: %{}
end
