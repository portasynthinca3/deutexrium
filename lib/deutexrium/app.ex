defmodule Deutexrium.App do
  use Application

  @impl true
  def start(_type, _args) do
    Deutexrium.Sup.start_link([])
  end
end
