defmodule Ctl do
  def shutdown do
    Deutexrium.Server.Supervisor.shutdown
  end

  def dump_model(channel) do
    Deutexrium.Persistence.Model.load!(channel)
  end
end
