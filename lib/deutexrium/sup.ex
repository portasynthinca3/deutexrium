defmodule Deutexrium.Sup do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [%{id: Deutexrium, start: {Deutexrium, :start_link, []}}]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
