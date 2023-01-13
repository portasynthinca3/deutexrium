defmodule Ctl do
  @moduledoc """
  Admin functions meant to be executed from the shell
  """

  alias Nostrum.Api
  alias Deutexrium.Translation

  defdelegate migrate(channel_id, limit), to: Deutexrium.Util.Migrate
  defdelegate migrate(channel_id), to: Deutexrium.Util.Migrate
  defdelegate migrate_all(), to: Deutexrium.Util.Migrate
  defdelegate observer, to: :observer_cli, as: :start
  defdelegate reload_langs, to: Translation, as: :reload

  def unload(resource), do:
    GenServer.cast({:via, Registry, {Registry.Server, resource}}, {:shutdown, false})

  def add_slash_commands(guild \\ 0) do
    commands = []

    # reset
    commands = [%{
      name: "reset",
      description: "reset something",
      default_member_permissions: "0",
      dm_permission: false,
      options: [
        %{
          type: 1, # subcommand
          name: "model",
          description: "reset the generation model of this channel",
        },
        %{
          type: 1, # subcommand
          name: "settings",
          description: "reset the settings of this channel",
        },
        %{
          type: 1, # subcommand
          name: "server",
          description: "reset the settings of this server",
        }
      ]
    } | commands]

    # zero-parameter commands
    no_param = [
      {"status", "key statistics", []},
      {"stats", "my resource usage. this isn't particularly interesting", [:dm]},
      {"gen_global", "immediately generate a message using the global model", []},
      {"donate", "ways to support me", []},
      {"privacy", "privacy policy", []},
      {"support", "ways to get support", []},
      {"scoreboard", "top-10 most active users on this server", []},
      {"impostor", "enable impersonation mode", [:adm]},
      {"settings", "configure settings", [:adm]},
      {"help", "show help", []},
      {"first_time_setup", "interactive first time setup", [:adm]}
    ]
    no_param = no_param |> Enum.map(fn {title, desc, flags} ->
      cmd = %{name: title, description: desc, dm_permission: false}
      Enum.reduce(flags, cmd, fn flag, cmd -> case flag do
        :dm -> Map.put(cmd, :dm_permission, true)
        :adm -> Map.put(cmd, :default_member_permissions, "0")
      end end)
    end)
    commands = commands ++ no_param

    # gen
    commands = [%{
      name: "generate",
      description: "generate message(s) using the current channel's model",
      dm_permission: false,
      options: [
        %{
          type: 4, # integer
          name: "count",
          description: "the number of messages to generate; defaults to 1",
          required: false
        }
      ]
    } | commands]

    # pre_train
    commands = [%{
      name: "pre_train",
      description: "trains the local model on previous messages in this channel",
      dm_permission: false,
      default_member_permissions: "0",
      options: [
        %{
          type: 4, # integer
          name: "count",
          description: "the number of previous messages to train on; defaults to 1k, max is 10k",
          required: false
        }
      ]
    } | commands]

    # generate_from
    commands = [%{
      name: "generate_from",
      description: "generate a message using the specified channel's model",
      dm_permission: false,
      options: [
        %{
          type: 7, # channel
          name: "channel",
          description: "the channel to use",
          required: true
        }
      ]
    } | commands]

    # Generate by them
    commands = [%{
      name: "gen_by_them",
      dm_permission: false,
      type: 2
    } | commands]

    # translate commands
    commands = for command <- commands do
      name = command.name
      command = Map.put(command, :name_localizations, Translation.translate_to_all("command.#{name}.title"))
      command = if Map.has_key?(command, :description) do
        Map.put(command, :description_localizations, Translation.translate_to_all("command.#{name}.description"))
      else command end

      if Map.has_key?(command, :options) do
        options = for option <- command.options do
          opt = option.name
          option
            |> Map.put(:name_localizations, Translation.translate_to_all("command.#{name}.option.#{opt}.title"))
            |> Map.put(:description_localizations, Translation.translate_to_all("command.#{name}.option.#{opt}.description"))
        end
        %{command | options: options}
      else command end
    end

    result = if guild == 0 do
      Api.bulk_overwrite_global_application_commands(commands)
    else
      Api.bulk_overwrite_guild_application_commands(guild, commands)
    end

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def remove_slash_commands(guild) do
    Api.bulk_overwrite_guild_application_commands(guild, [])
  end
end
