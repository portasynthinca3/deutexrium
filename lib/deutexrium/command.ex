defmodule Deutexrium.Command do
  use Nostrum.Consumer
  @moduledoc """
  Handles interactions and other events and passes them down to the handling modules
  """

  require Logger
  alias Nostrum.{Api, Struct.Interaction}
  alias Deutexrium.CommandHolder

  defmacro __using__(_) do
    quote do
      @behaviour Deutexrium.Command
    end
  end
  defmodule WithDefaultImports do
    @moduledoc "Implements Command with useful default imports"
    defmacro __using__(_) do
      quote do
        @behaviour Deutexrium.Command
        alias Nostrum.{Api, Struct}
        alias Deutexrium.Server
        import Deutexrium.Translation, only: [translate: 2, translate: 3]
      end
    end
  end

  @type cmd_flag() :: :admin | :dm | :defer | :ephemeral
  @type cmd_spec() :: %{
    :name => String.t,
    optional(:flags) => [cmd_flag()],
    optional(:options) => [map()]
  }

  @callback spec() :: cmd_spec()
  @callback handle_command(Interaction.t) :: term()
  @callback handle_other({atom(), term(), term()}) :: term()
  @optional_callbacks handle_other: 1

  def start_link(), do: Consumer.start_link(__MODULE__)

  def handle_event({:READY, _, _}), do: Logger.info("started consumer")

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: command}} = interaction, _}) when command != nil do
    Logger.debug("received /#{command}")

    {module, flags} = CommandHolder.get_module(command)
    if :defer in flags do
      flags = if :ephemeral in flags do 64 else 0 end
      Api.create_interaction_response!(interaction, %{type: 5, data: %{flags: flags}})
    end

    {us, result} = :timer.tc(fn -> module.handle_command(interaction) end)
    Deutexrium.Prometheus.command_handled(command, us)

    case result do
      :ok ->
        :ok

      data when is_map(data) ->
        Api.edit_interaction_response!(interaction, data)

      {:finish, data, finish} ->
        Api.edit_interaction_response!(interaction, data)
        module.finish_handling(finish)

      {:delete_and_finish, finish} ->
        Api.delete_interaction_response!(interaction)
        module.finish_handling(finish)
    end
  end

  def handle_event(event) do
    for {_, module, flags} <- CommandHolder.list_commands do
      if :handles_other in flags do
        module.handle_other(event)
      end
    end
  end
end
