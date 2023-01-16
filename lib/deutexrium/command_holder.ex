defmodule Deutexrium.CommandHolder do
  use GenServer
  @moduledoc """
  Holds a ETS table with command information and populates it when requested
  """

  require Logger
  alias Deutexrium.{Command, Translation}

  @command_modules [
    Command.Support
  ]

  def start_link(init_args), do: GenServer.start_link(__MODULE__, [init_args], name: __MODULE__)

  def init(_args) do
    table = :ets.new(:commands, [:named_table, :public, :set])
    reload_cmds(table)
    {:ok, table}
  end

  defp reload_cmds(table) do
    :ets.delete_all_objects(table)

    commands = @command_modules |> Enum.map(fn module ->
      source_spec = module.spec() |> Map.put(:dm_permission, false)
      name = source_spec.name
      spec = %{name: name}

      # add name and description localizations
      spec = Map.put(spec, :name_localizations, Translation.translate_to_all("command.#{name}.title"))
      spec = Map.put(spec, :description, Translation.translate("en-US", "command.#{name}.description"))
      spec = Map.put(spec, :description_localizations, Translation.translate_to_all("command.#{name}.description"))

      # add option localizations
      spec = if Map.has_key?(source_spec, :options) do
        options = for option <- source_spec.options do
          opt = option.name
          option
            |> Map.put(:name_localizations, Translation.translate_to_all("command.#{name}.option.#{opt}.title"))
            |> Map.put(:description, Translation.translate("en-US", "command.#{name}.option.#{opt}.description"))
            |> Map.put(:description_localizations, Translation.translate_to_all("command.#{name}.option.#{opt}.description"))
        end
        Map.put(spec, :options, options)
      else spec end

      # process flags
      spec = if Map.has_key?(source_spec, :flags) do
        Enum.reduce(source_spec.flags, spec, fn flag, spec ->
          case flag do
            :admin -> Map.put(spec, :default_member_permissions, "0")
            :dm -> Map.put(spec, :dm_permission, true)
            _ -> spec
          end
        end)
      else spec end

      flags = Map.get(source_spec, :flags, [])
      spec = Map.delete(spec, :flags)

      {module, spec, flags}
    end)

    # register
    Nostrum.Api.bulk_overwrite_global_application_commands(
      Nostrum.Api.get_current_user!().id,
      commands |> Enum.map(fn {_, spec, _} -> spec end)
    )

    # update the table
    for {module, spec, flags} <- commands do
      flags = if function_exported?(module, :handle_other, 1) do
        [:handles_other | flags]
      else flags end
      :ets.insert(table, {spec.name, module, flags})
    end

    Logger.info("reloaded #{length(commands)} commands")
  end

  def handle_call(:reload, _from, table) do
    reload_cmds(table)
    {:reply, :ok, table}
  end

  # PUBLIC INTERFACE

  def reload(), do: GenServer.call(__MODULE__, :reload)

  def get_module(command) do
    case :ets.lookup(:commands, command) do
      [{_, mod, flags}] -> {mod, flags}
      [] -> raise ArgumentError, "unregistered command: /#{command}"
    end
  end

  def list_commands, do: :ets.lookup(:translation_keys, :languages)
end
