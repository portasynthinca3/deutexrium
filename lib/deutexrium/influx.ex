defmodule Deutexrium.Influx do
  use Instream.Connection, otp_app: :deutexrium
end

defmodule Deutexrium.Influx.Cpu do
  use Instream.Series
  series do
    measurement "cpu"
    tag :host
    field :value
  end
end

defmodule Deutexrium.Influx.Memory do
  use Instream.Series
  series do
    measurement "memory"
    tag :host
    field :value
  end
end

defmodule Deutexrium.Influx.Guilds do
  use Instream.Series
  series do
    measurement "guilds"
    tag :host
    field :value
  end
end

defmodule Deutexrium.Influx.Channels do
  use Instream.Series
  series do
    measurement "channels"
    tag :host
    field :value
  end
end

defmodule Deutexrium.Influx.Train do
  use Instream.Series
  series do
    measurement "train"
    tag :host
    field :value
  end
end

defmodule Deutexrium.Influx.Gen do
  use Instream.Series
  series do
    measurement "gen"
    tag :host
    field :value
  end
end



defmodule Deutexrium.Influx.Logger do
  alias Deutexrium.Influx.{Cpu, Memory, Guilds, Channels, Train, Gen}
  require Logger

  defp point(data, tags, fields) do
    %{
      data |
      fields: Map.merge(data.fields, fields),
      tags: Map.merge(data.tags, tags)
    }
  end

  defp write do
    {:ok, host} = :inet.gethostname()
    %{guilds: guilds, channels: channels} = Deutexrium.Server.Supervisor.server_count
    %{train: train, gen: gen} = Deutexrium.Influx.LoadCntr.get_state
    mem = :erlang.memory(:total) |> div(1024 * 1024)
    cpu = :cpu_sup.avg1 / 25.6

    Logger.debug("writing data to Influx")
    [
      point(%Cpu{}, %{host: host}, %{value: cpu}),
      point(%Memory{}, %{host: host}, %{value: mem}),
      point(%Guilds{}, %{host: host}, %{value: guilds}),
      point(%Channels{}, %{host: host}, %{value: channels}),
      point(%Train{}, %{host: host}, %{value: train}),
      point(%Gen{}, %{host: host}, %{value: gen})
    ]
    |> Deutexrium.Influx.write()
  end

  def log do
    interval = Application.fetch_env!(:deutexrium, :log_interval)
    receive do after interval ->
      write()
      log()
    end
  end
end

defmodule Deutexrium.Influx.LoadCntr do
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
