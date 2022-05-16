defmodule Deutexrium.Influx do
  @moduledoc """
  Manages InfluxDB logging
  """

  use Instream.Connection, otp_app: :deutexrium

  defmodule Series do
    @moduledoc """
    Hosts submodules describing data points
    """
    defmodule Cpu do
      @moduledoc false
      use Instream.Series
      series do
        measurement "cpu"
        tag :host
        field :value
      end
    end
    defmodule Memory do
      @moduledoc false
      use Instream.Series
      series do
        measurement "memory"
        tag :host
        field :value
      end
    end
    defmodule Guilds do
      @moduledoc false
      use Instream.Series
      series do
        measurement "guilds"
        tag :host
        field :value
      end
    end
    defmodule Channels do
      @moduledoc false
      use Instream.Series
      series do
        measurement "channels"
        tag :host
        field :value
      end
    end
    defmodule Train do
      @moduledoc false
      use Instream.Series
      series do
        measurement "train"
        tag :host
        field :value
      end
    end
    defmodule Gen do
      @moduledoc false
      use Instream.Series
      series do
        measurement "gen"
        tag :host
        field :value
      end
    end
    defmodule KnownGuilds do
      @moduledoc false
      use Instream.Series
      series do
        measurement "k_guilds"
        tag :host
        field :value
      end
    end
    defmodule KnownChannels do
      @moduledoc false
      use Instream.Series
      series do
        measurement "k_channels"
        tag :host
        field :value
      end
    end
  end
end

defmodule Deutexrium.Influx.Logger do
  use GenServer
  @moduledoc "Logs usage stats to InfluxDB"

  alias Deutexrium.Influx.Series
  require Logger

  defp point(data, tags, fields) do
    %{
      data |
      fields: Map.merge(data.fields, fields),
      tags: Map.merge(data.tags, tags)
    }
  end

  def init(_) do
    interval = Application.fetch_env!(:deutexrium, :log_interval)
    Process.send_after(self(), :write, interval)
    {:ok, interval}
  end

  def handle_info(:write, interval) do
    # collect stats
    {:ok, host} = :inet.gethostname
    %{guild: guilds, channel: channels} = Deutexrium.Server.RqRouter.server_count
    %{train: train, gen: gen} = Deutexrium.Influx.LoadCntr.get_state
    mem = :erlang.memory(:total) |> div(1024 * 1024)
    cpu = :cpu_sup.avg1 / 2.56
    k_guilds = Nostrum.Cache.GuildCache.all |> Enum.count

    # write them
    Logger.debug("writing data to Influx")
    [
      point(%Series.Cpu{}, %{host: host}, %{value: cpu}),
      point(%Series.Memory{}, %{host: host}, %{value: mem}),
      point(%Series.Guilds{}, %{host: host}, %{value: guilds}),
      point(%Series.Channels{}, %{host: host}, %{value: channels}),
      point(%Series.Train{}, %{host: host}, %{value: train}),
      point(%Series.Gen{}, %{host: host}, %{value: gen}),
      point(%Series.KnownGuilds{}, %{host: host}, %{value: k_guilds}),
    ]
    |> Deutexrium.Influx.write

    Process.send_after(self(), :write, interval)
    {:noreply, interval}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
end

defmodule Deutexrium.Influx.LoadCntr do
  @moduledoc """
  Shared load counter
  """

  use GenServer
  require Logger

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.debug("LoadCntr started")
    {:ok, %{gen: 0, train: 0}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:add, key}, state) do
    Logger.debug("#{inspect key} +1")
    state = %{state | key => state[key] + 1}
    Process.send_after(self(), {:"$gen_cast", {:sub, key}}, 5000)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:sub, key}, state) do
    Logger.debug("#{inspect key} -1")
    state = %{state | key => state[key] - 1}
    {:noreply, state}
  end


  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end
  def add(key) do
    GenServer.cast(__MODULE__, {:add, key})
  end
  def sub(key) do
    GenServer.cast(__MODULE__, {:sub, key})
  end
end
