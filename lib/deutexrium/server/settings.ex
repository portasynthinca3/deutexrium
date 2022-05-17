defmodule Deutexrium.Server.Settings do
  use GenServer
  @moduledoc """
  Supports a /settings session
  """
  alias Deutexrium.Server.{Channel, Guild, RqRouter}

  defmodule State do
    @moduledoc "Setting server state"
    defstruct guild: nil,
              channel: nil,
              context: :guild,
              timeout: 60_000,
              inter: :nil
  end

  @settings [
    %{value: :train,
      name: "Train model"},

    %{value: :global_train,
      name: "Train global model"},

    %{value: :ignore_bots,
      name: "Ignore bots"},

    %{value: :remove_mentions,
      name: "Remove mentions"},

    %{value: :autogen_rate,
      type: :int,
      range: 0..1000,
      name: "Automatic generation rate"},

    %{value: :max_gen_len,
      type: :int,
      range: 1..25,
      name: "Top /gen option value"},

    %{value: :impostor_rate,
      type: :int,
      range: 0..100,
      name: "Impersonation rate"}
  ]


  defp generate_bin_button(settings, setting) do
    value = Map.get(settings, setting.value)

    val_to_str = &case &1 do
      nil -> "no override"
      true -> "on"
      false -> "off"
    end

    %{
      type: 2, # button
      style: case value do
        nil -> 2 # grey
        true -> 3 # green
        false -> 4 # red
      end,
      label: "#{setting.name}: #{val_to_str.(value)}",
      custom_id: :erlang.atom_to_binary(setting.value)
    }
  end

  defp generate_nb_row(settings, setting) do
    value = Map.get(settings, setting.value)
    value_label = if value == nil do "no override" else value end

    disabled = &if :erlang.is_integer(value) do
      value + &1 not in setting.range
    else true end

    %{type: 1, components: [
      %{type: 2, label: "#{setting.name}: #{value_label}", custom_id: "nil_#{setting.value}", style: 2},
      %{type: 2, label: "-10", style: 2, custom_id: "int_#{setting.value}-10", disabled: disabled.(-10)},
      %{type: 2, label: "-1", style: 2, custom_id: "int_#{setting.value}-1", disabled: disabled.(-1)},
      %{type: 2, label: "+1", style: 2, custom_id: "int_#{setting.value}+1", disabled: disabled.(+1)},
      %{type: 2, label: "+10", style: 2, custom_id: "int_#{setting.value}+10", disabled: disabled.(+10)}
    ]}
  end

  defp generate_components(%State{} = state) do
    # get settings
    settings = case state.context do
      :guild -> Guild.get_meta(state.guild)
      channel_id -> Channel.get_meta({channel_id, state.guild})
    end

    # acquire list of channels in guild
    channels = Nostrum.Cache.GuildCache.get!(state.guild).channels
      |> Map.values
      |> Enum.filter(&(&1.type == 0)) # leave text ones only
      |> Enum.sort_by(&{&1.id != state.channel, &1.id}) # current channel first, other chanels by id
      |> Enum.take(24) # limit to 24

    # get settings by category
    {nonbin, bin} = Enum.split_with(@settings, &Map.has_key?(&1, :type))

    # construct lines for binary settings
    bin_rows = bin
      |> Enum.map(&generate_bin_button(settings, &1))
      |> Enum.chunk_every(5)
      |> Enum.map(&%{type: 1, components: &1}) # make each row into a map

    # construct lines for nb settings
    nb_rows = nonbin
      |> Enum.map(&generate_nb_row(settings, &1))

    [
      # channel select
      %{type: 1, components: [
        %{
          type: 3, # select menu
          custom_id: "settings_target",
          options: [
            %{
              label: "Server",
              value: "server",
              description: "Applies to all channels, except when they're overridden",
              emoji: %{name: "server", id: "974707196573143120"},
              default: state.context == :guild
            } | Enum.map(channels, &%{
              label: &1.name,
              value: &1.id,
              emoji: %{name: "channel", id: "974705757691981894"},
              default: state.context == &1.id,
              description: if state.channel == &1.id do "Current channel" else nil end
            })
          ]
        }
      ]}
      # other rows
      | Enum.concat(bin_rows, nb_rows)
    ]
  end

  @impl true
  def init({channel, guild}) do
    state = %State{guild: guild, channel: channel}
    {:ok, state, state.timeout}
  end


  @impl true
  def handle_call({:initialize, inter}, _from, %State{} = state) do
    {:reply, generate_components(state), %{
      state | inter: inter
    }, state.timeout}
  end

  def handle_call({:switch_ctx, ctx}, _from, %State{} = state) do
    state = %{state | context: ctx}
    {:reply, {state.inter, generate_components(state)}, state, state.timeout}
  end

  def handle_call({:clicked, setting}, _from, %State{} = state) do
    get_meta = &case &1 do
      :cur -> case state.context do
        :guild -> Guild.get_meta(state.guild)
        channel_id -> Channel.get_meta({channel_id, state.guild})
      end
      :guild -> Guild.get_meta(state.guild)
      :channel -> Channel.get_meta({state.context, state.guild})
    end

    # get setting atom and value
    {setting, value} = cond do
      # integer increment
      String.starts_with?(setting, "int_") ->
        [_, setting, sign, inc] = Regex.run(~r/int_(.+)([+-])(\d+)/, setting)
        setting = :erlang.binary_to_atom(setting)
        inc = :erlang.binary_to_integer(inc)
        inc = if sign == "-" do 0 - inc else inc end
        value = get_meta.(:cur) |> Map.get(setting)
        {setting, value + inc}

      # (un-)nil
      String.starts_with?(setting, "nil_") ->
        setting = :erlang.binary_to_atom(setting |> String.slice(4..-1))
        case state.context do
          :guild -> {setting, :nochange}
          _ -> {
            setting,
            if get_meta.(:channel) |> Map.get(setting) == nil do
              get_meta.(:guild) |> Map.get(setting)
            else nil end
          }
        end

      # on/off/(nil)
      true ->
        {meta, map} = case state.context do
          :guild -> {get_meta.(:guild), %{true: false, false: true}}
          _channel -> {get_meta.(:channel), %{true: false, false: nil, nil: true}}
        end
        setting = :erlang.binary_to_atom(setting)
        current = meta |> Map.get(setting)
        {setting, map |> Map.get(current)}
    end

    # modify setting
    unless value == :nochange do
      case state.context do
        :guild -> Guild.set(state.guild, setting, value)
        channel_id -> Channel.set({channel_id, state.guild}, setting, value)
      end
    end

    {:reply, {state.inter, generate_components(state)}, state, state.timeout}
  end


  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end



  # API

  @type id() :: {integer(), integer()}

  @spec initialize(id(), any) :: %{}
  def initialize(id, inter) do
    id |> RqRouter.route_to_settings({:initialize, inter})
  end

  @spec switch_ctx(id(), :guild|integer()) :: {any, %{}}
  def switch_ctx(id, ctx) do
    id |> RqRouter.route_to_settings({:switch_ctx, ctx})
  end

  @spec clicked(id(), String.t()) :: {any, %{}}
  def clicked(id, setting) do
    id |> RqRouter.route_to_settings({:clicked, setting})
  end
end
