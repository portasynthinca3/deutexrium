defmodule Ctl do
  def shutdown do
    Deutexrium.Server.Supervisor.shutdown
  end
end
