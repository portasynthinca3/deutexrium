defmodule Deutexrium.Prometheus do
  use GenServer
  @moduledoc "Sets up all and logs periodic metrics"

  use Prometheus

  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  def init(_) do
    Deutexrium.Prometheus.Plug.setup()

    Histogram.declare([
      name: :deutex_cmd_execute,
      labels: [:command],
      buckets: {:linear, 0, 500_000, 10},
      help: "Command execution & response time (us)"
    ])

    _ = [
      [name: :deutex_data_size, help: "User data size"],
      [name: :deutex_processes, help: "BEAM processes"],
      [name: :deutex_ports,     help: "BEAM ports"],
    ] |> Enum.map(&Gauge.declare/1)

    interval = Application.get_env(:deutexrium, :log_interval)
    Process.send_after(self(), :log, 0)
    {:ok, interval}
  end

  def handle_info(:log, interval) do
    Gauge.set([name: :deutex_processes], Process.list |> length())
    Gauge.set([name: :deutex_ports], Port.list |> length())

    Process.send_after(self(), :log, interval)
    {:noreply, interval}
  end

  def command_handled(command, time) do
    Histogram.observe([
      name: :deutex_cmd_execute,
      labels: [command]
    ], time)
  end

  def data_size(size), do: Gauge.set([name: :deutex_data_size], size)

  defmodule Plug do
    use Prometheus.PlugExporter
  end
end
