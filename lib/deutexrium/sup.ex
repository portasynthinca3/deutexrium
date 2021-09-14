defmodule Deutexrium.Sup do
  use Supervisor
  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop do
    Supervisor.stop(__MODULE__)
    Logger.notice("supervisor stopped")
  end

  @impl true
  def init(_init_arg) do
    children = [Deutexrium]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
