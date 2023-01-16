defmodule Deutexrium.Server.Settings do
  use GenServer
  @moduledoc """
  Supports /settings and /first_time_setup sessions
  """
  alias Deutexrium.Server.{Channel, Guild, RqRouter}
  alias Nostrum.Api
  import Deutexrium.Translation, only: [translate: 2, translate: 3]

  defmodule FTS do
    @moduledoc "First Time Setup state"
    defstruct step_history: [0],
              changes: [],
              step_data: nil
  end

  defmodule State do
    @moduledoc "Setting server state"
    defstruct guild: nil,
              channel: nil,
              context: :guild,
              timeout: 5 * 60_000,
              inter: nil,
              fts: nil
  end

  @settings [
    %{value: :train},
    %{value: :global_train},
    %{value: :ignore_bots},
    %{value: :remove_mentions},

    %{value: :autogen_rate,
      type: :int,
      range: 0..1000},

    %{value: :max_gen_len,
      type: :int,
      range: 1..25},

    %{value: :impostor_rate,
      type: :int,
      range: 0..100}
  ]

  @fts_steps [
    welcome:            %{type: :plain},

    collection:         %{type: :channel_sel,      put_in: :train},
    global_collection:  %{type: :channel_sel,      put_in: :global_train},
    mention_removal:    %{type: :channel_sel,      put_in: :remove_mentions},
    autogen:            %{type: :guild_nb_setting, put_in: :autogen_rate},
    impostor:           %{type: :channel_sel,      put_in: :impostor},

    accept:             %{type: :accept},
    applying:           %{type: :applying},
    accepted:           %{type: :accepted},

    aborted:            %{type: :aborted}
  ]


  defp generate_bin_button(settings, setting, locale) do
    value = Map.get(settings, setting.value)

    val_to_str = &case &1 do
      nil -> translate(locale, "setting.bin_value.no_override")
      true -> translate(locale, "setting.bin_value.on")
      false -> translate(locale, "setting.bin_value.off")
    end

    title = translate(locale, "setting.name.#{:erlang.atom_to_binary(setting.value)}")

    %{
      type: 2, # button
      style: case value do
        nil -> 2 # grey
        true -> 3 # green
        false -> 4 # red
      end,
      label: "#{title}: #{val_to_str.(value)}",
      custom_id: :erlang.atom_to_binary(setting.value)
    }
  end

  defp generate_nb_row(settings, setting, locale) do
    value = Map.get(settings, setting.value)
    value_label = if value == nil do translate(locale, "setting.bin_value.no_override") else value end

    disabled = &if :erlang.is_integer(value) do
      value + &1 not in setting.range
    else true end

    title = translate(locale, "setting.name.#{:erlang.atom_to_binary(setting.value)}")
    %{type: 1, components: [
      %{type: 2, label: "#{title}: #{value_label}", custom_id: "nil_#{setting.value}", style: 2},
      %{type: 2, label: "-10", style: 2, custom_id: "int_#{setting.value}-10", disabled: disabled.(-10)},
      %{type: 2, label: "-1", style: 2, custom_id: "int_#{setting.value}-1", disabled: disabled.(-1)},
      %{type: 2, label: "+1", style: 2, custom_id: "int_#{setting.value}+1", disabled: disabled.(+1)},
      %{type: 2, label: "+10", style: 2, custom_id: "int_#{setting.value}+10", disabled: disabled.(+10)}
    ]}
  end

  defp generate_components(%State{fts: nil} = state) do
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
      |> Enum.map(&generate_bin_button(settings, &1, state.inter.locale))
      |> Enum.chunk_every(5)
      |> Enum.map(&%{type: 1, components: &1}) # make each row into a map

    # construct lines for nb settings
    nb_rows = nonbin
      |> Enum.map(&generate_nb_row(settings, &1, state.inter.locale))

    {nil, [
      # channel select
      %{type: 1, components: [
        %{
          type: 3, # select menu
          custom_id: "settings_target",
          options: [
            %{
              label: "Server",
              value: "server",
              description: translate(state.inter.locale, "setting.server"),
              emoji: %{name: "server", id: "974707196573143120"},
              default: state.context == :guild
            } | Enum.map(channels, &%{
              label: &1.name,
              value: &1.id,
              emoji: %{name: "channel", id: "974705757691981894"},
              default: state.context == &1.id,
              description: if state.channel == &1.id do translate(state.inter.locale, "setting.current") else nil end
            })
          ]
        }
      ]}
      # other rows
      | Enum.concat(bin_rows, nb_rows)
    ]}
  end

  defp generate_components(%State{fts: %FTS{step_history: [step | _]} = fts} = state) do
    locale = state.inter.locale
    {step_name, step_spec} = Enum.at(@fts_steps, step)

    {text, btns, other, disable_next} = case step_spec.type do
      :plain ->
        text = translate(locale, "first_time_setup.steps.#{step_name}")
        {text, [:abort, :prev, :next], nil, false}

      :channel_sel when fts.step_data == nil ->
        text = translate(locale, "first_time_setup.steps.#{step_name}")
        {text, [:abort, :prev, :next], [
          %{type: 2, label: translate(locale, "first_time_setup.common.channel_sel.all"),        style: 2, custom_id: "fts_all"},
          %{type: 2, label: translate(locale, "first_time_setup.common.channel_sel.some"),       style: 2, custom_id: "fts_some"},
          %{type: 2, label: translate(locale, "first_time_setup.common.channel_sel.all_except"), style: 2, custom_id: "fts_allex"},
          %{type: 2, label: translate(locale, "first_time_setup.common.channel_sel.none"),       style: 2, custom_id: "fts_none"},
        ], true}

      :channel_sel ->
        {nil, [:abort, :prev, :next], [%{
          type: 8,
          placeholder: translate(locale, "first_time_setup.common.channel_sel.restriction"),
          custom_id: "fts_channels",
          min_values: 1,
          channel_types: [0],
          max_values: 25
        }], true}

      :guild_nb_setting ->
        text = """
        #{translate(locale, "first_time_setup.steps.#{step_name}")}
        #{translate(locale, "first_time_setup.common.guild_nb_setting", ["#{fts.step_data || 0}"])}
        """
        {text, [:abort, :prev, :next], [
          %{type: 2, label: "-10", style: 2, custom_id: "fts_-10"},
          %{type: 2, label: "-1",  style: 2, custom_id: "fts_-1"},
          %{type: 2, label: "+1",  style: 2, custom_id: "fts_+1"},
          %{type: 2, label: "+10", style: 2, custom_id: "fts_+10"},
        ], false}

      :accept ->
        changes = fts.changes |> Enum.map_join("\n", fn {key, val} ->
          {_, spec} = Enum.find(@fts_steps, fn {_, spec} -> Map.has_key?(spec, :put_in) and spec.put_in == key end)
          {k, v} = case {spec.type, val} do
            {:channel_sel, t} when t == :all or t == :none -> {
                translate(locale, "first_time_setup.steps.#{step_name}.entry.#{spec.put_in}"),
                translate(locale, "first_time_setup.steps.#{step_name}.channels.#{t}")
              }
            {:channel_sel, {t, list}} when t == :some or t == :all_except -> {
                translate(locale, "first_time_setup.steps.#{step_name}.entry.#{spec.put_in}"),
                translate(locale, "first_time_setup.steps.#{step_name}.channels.#{t}", [list |> Enum.map_join(", ", fn x -> "<##{x}>" end)])
              }
            {:guild_nb_setting, val} -> {
                translate(locale, "first_time_setup.steps.#{step_name}.entry.#{spec.put_in}", ["#{val}"]),
                nil
              }
          end
          "      - #{k} #{v}"
        end)
        text = translate(locale, "first_time_setup.steps.#{step_name}.text", [changes])
        {text, [:abort, :prev, :accept], nil, true}

      :applying ->
        text = translate(locale, "first_time_setup.steps.#{step_name}")
        {text, [:next], nil, true}

      :accepted ->
        wh_errors = fts.step_data |> Enum.filter(fn
          {:access, _} -> true
          _ -> false
        end) |> Enum.map(fn {:access, id} -> id end)

        errors = []
        errors = if length(wh_errors) > 0 do
          channels = Enum.map_join(wh_errors, ", ", fn x -> "<##{x}>" end)
          errors ++ [
            "      - #{translate(locale, "first_time_setup.steps.accepted.error.impostor", [channels])}"
          ]
        else errors end

        ttd = translate(locale, "first_time_setup.steps.#{step_name}.text.things_to_do")
        text = if errors == [] do
          translate(locale, "first_time_setup.steps.#{step_name}.text.ok", [ttd])
        else
          translate(locale, "first_time_setup.steps.#{step_name}.text.error", [Enum.join(errors, "\n"), ttd])
        end
        {text, [:prev], nil, true}

      :aborted ->
        text = translate(locale, "first_time_setup.steps.#{step_name}")
        {text, [:prev], nil, false}
    end

    btns = Enum.map(btns, fn
      :abort  -> %{type: 2, label: translate(locale, "first_time_setup.common.bottom_row.abort"),  style: 4, custom_id: "fts_abort"}
      :prev   -> %{type: 2, label: translate(locale, "first_time_setup.common.bottom_row.prev"),   style: 2, custom_id: "fts_prev", disabled: length(fts.step_history) < 2}
      :next   -> %{type: 2, label: translate(locale, "first_time_setup.common.bottom_row.next"),   style: 1, custom_id: "fts_next", disabled: disable_next}
      :accept -> %{type: 2, label: translate(locale, "first_time_setup.common.bottom_row.accept"), style: 3, custom_id: "fts_accept"}
    end)

    components = if other do
      [%{type: 1, components: other}, %{type: 1, components: btns}]
    else [%{type: 1, components: btns}] end

    {text, components}
  end

  @impl true
  def init({channel, guild}) do
    state = %State{guild: guild, channel: channel}
    {:ok, state, state.timeout}
  end


  @impl true
  def handle_call({:initialize, inter}, _from, %State{} = state) do
    state = %{state | inter: inter}
    state = if inter.data.name == "first_time_setup" do
      %{state | fts: %FTS{}}
    else state end
    {:reply, generate_components(state), state, state.timeout}
  end

  def handle_call({:switch_ctx, inter, ctx}, _from, %State{} = state) do
    old_inter = state.inter
    state = %{state | context: ctx, inter: inter}
    {:reply, {old_inter, generate_components(state)}, state, state.timeout}
  end

  def handle_call({:clicked, inter, setting}, _from, %State{fts: nil} = state) do
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

    old_inter = state.inter
    state = %{state | inter: inter}

    {:reply, {old_inter, generate_components(state)}, state, state.timeout}
  end

  def handle_call({:clicked, inter, btn_id}, _from, %State{fts: %FTS{step_history: [step | _]} = fts} = state) do
    {_step_name, step_spec} = Enum.at(@fts_steps, step)

    state = case btn_id do
      "fts_channels" ->
        channels = inter.data.values |> Enum.map(fn x ->
          {x, _} = Integer.parse(x)
          x
        end)
        %{state | fts: %{fts |
          step_history: [step + 1 | fts.step_history],
          changes: Keyword.put(fts.changes, step_spec.put_in, {fts.step_data, channels}),
          step_data: nil
        }}

      "fts_next" when fts.step_data == nil ->
        %{state | fts: %{fts | step_history: [step + 1 | fts.step_history]}}
      "fts_next" ->
        %{state | fts: %{fts |
          step_history: [step + 1 | fts.step_history],
          changes: Keyword.put(fts.changes, step_spec.put_in, fts.step_data),
          step_data: nil
        }}

      "fts_prev" when fts.step_data == nil ->
        [_ | prev] = fts.step_history
        %{state | fts: %{fts | step_history: prev, step_data: nil}}
      "fts_prev" ->
        %{state | fts: %{fts | step_data: nil}}

      "fts_abort" ->
        %{state | fts: %{fts |
          step_history: [Enum.find_index(@fts_steps, fn {x, _} -> x == :aborted end)],
          changes: [],
          step_data: nil
        }}

      x when x == "fts_all" or x == "fts_none" ->
        %{state | fts: %{fts |
          step_history: [step + 1 | fts.step_history],
          changes: Keyword.put(fts.changes, step_spec.put_in, if x == "fts_all" do :all else :none end)
        }}

      x when x == "fts_some" or x == "fts_allex" ->
        %{state | fts: %{fts |
          step_history: [step | fts.step_history],
          step_data: if x == "fts_some" do :some else :all_except end
        }}

      "fts_-10" -> %{state | fts: %{fts | step_data: (fts.step_data || 0) - 10}}
      "fts_-1"  -> %{state | fts: %{fts | step_data: (fts.step_data || 0) - 1}}
      "fts_+1"  -> %{state | fts: %{fts | step_data: (fts.step_data || 0) + 1}}
      "fts_+10" -> %{state | fts: %{fts | step_data: (fts.step_data || 0) + 10}}

      "fts_accept" ->
        send(self(), :fts_accept)
        %{state | fts: %{fts | step_history: [step + 1 | fts.step_history]}}
    end

    old_inter = state.inter
    state = %{state | inter: inter}
    {:reply,
      {old_inter, generate_components(state)},
      if btn_id == "fts_abort" do %{state | fts: nil} else state end,
      state.timeout}
  end


  @impl true
  def handle_info(:timeout, state) do
    Api.delete_interaction_response(state.inter)
    {:stop, :normal, state}
  end

  def handle_info(:fts_accept, state) do
    guild = state.inter.guild_id
    all_channels = Api.get_guild_channels!(guild) |> Enum.map(fn x -> x.id end)

    errors = for {key, val} <- state.fts.changes do
      {_, spec} = Enum.find(@fts_steps, fn {_, spec} -> Map.has_key?(spec, :put_in) and spec.put_in == key end)
      if key != :impostor do
        case {spec.type, val} do
          {:channel_sel, x} when x == :all or x == :none ->
            Deutexrium.Server.Guild.set(guild, key, x == :all)
            for id <- all_channels, do: Deutexrium.Server.Channel.set({id, guild}, key, nil)

          {:channel_sel, {x, overrides}} when x == :some or x == :all_except ->
            Deutexrium.Server.Guild.set(guild, key, x == :all_except)
            for id <- overrides, do: Deutexrium.Server.Channel.set({id, guild}, key, x == :some)

          {:guild_nb_setting, _} ->
            Deutexrium.Server.Guild.set(guild, key, val)
            for id <- all_channels, do: Deutexrium.Server.Channel.set({id, guild}, key, nil)
        end
        []
      else
        for id <- all_channels, do: Deutexrium.Server.Channel.set({id, guild}, :webhook_data, nil)
        case val do
          :none -> []
          {:some, overrides} -> overrides
          {:all_except, overrides} -> all_channels -- overrides
          :all -> all_channels
        end |> Enum.map(fn id ->
          case Api.create_webhook(id, %{name: "Deuterium impersonation mode", avatar: "https://cdn.discordapp.com/embed/avatars/0.png"}, "create webhook for impersonation") do
            {:ok, %{id: hook_id, token: hook_token}} ->
              data = {hook_id, hook_token}
              Deutexrium.Server.Channel.set({id, guild}, :webhook_data, data)
              :ok
            {:error, %{status_code: 403}} -> {:access, id}
            {:error, err} -> {err, id}
          end
        end) |> Enum.filter(fn x -> x != :ok end)
      end
    end |> List.flatten

    [step | _] = state.fts.step_history
    state = %{state | fts: %{state.fts | step_history: [step + 1], step_data: errors}}
    {text, components} = generate_components(state)
    Api.edit_interaction_response!(state.inter, %{content: text, components: components, flags: 64})

    state = %{state | fts: nil}
    {:noreply, state}
  end



  # API

  @spec initialize(any()) :: {String.t | nil, %{}}
  def initialize(inter) do
    RqRouter.route_to_settings({inter.channel_id, inter.guild_id}, {:initialize, inter})
  end

  @spec switch_ctx(any(), :guild | integer()) :: {any, {String.t | nil, %{}}}
  def switch_ctx(inter, ctx) do
    RqRouter.route_to_settings({inter.channel_id, inter.guild_id}, {:switch_ctx, inter, ctx})
  end

  @spec clicked(any(), String.t()) :: {any, {String.t | nil, %{}}}
  def clicked(inter, setting) do
    RqRouter.route_to_settings({inter.channel_id, inter.guild_id}, {:clicked, inter, setting})
  end
end
