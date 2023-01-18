defmodule Deutexrium.Persistence do
  use GenServer
  @moduledoc """
  Storage umbrella functions
  """

  require Logger

  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)
  def init(_) do
    interval = Application.get_env(:deutexrium, :usage_recalc_interval)
    Process.send_after(self(), :calculate_usage, 0)
    {:ok, {0, interval}}
  end
  def handle_info(:calculate_usage, interval) do
    Logger.debug("calculating disk usage")
    Process.send_after(self(), :calculate_usage, 60_000)
    size = calculate_used_space()
    Deutexrium.Prometheus.data_size(size)
    {:noreply, {size, interval}}
  end
  def handle_call(:storage_size, _from, {size, _} = state) do
    {:reply, size, state}
  end

  def calculate_used_space(path \\ Application.fetch_env!(:deutexrium, :data_path)) do
    File.ls!(path) |> Enum.reduce(0, fn file, acc ->
      stat = File.stat!(Path.join(path, file))
      if stat.type == :directory do
        acc + calculate_used_space(Path.join(path, file))
      else
        acc + stat.size
      end
    end)
  end

  def guild_cnt do
    path = Application.fetch_env!(:deutexrium, :data_path)
    File.ls!(path) |> Enum.count(fn x -> String.starts_with?(x, "guild_") end)
  end

  def chan_cnt do
    path = Application.fetch_env!(:deutexrium, :data_path)
    File.ls!(path) |> Enum.count(fn x -> String.starts_with?(x, "model_") end)
  end

  def allowed_vc do
    path = Application.fetch_env!(:deutexrium, :data_path)
    File.read!(Path.join(path, "voice"))
        |> String.split("\n")
        |> Enum.filter(fn x -> String.length(x) >= 1 end)
        |> Enum.map(&String.to_integer/1)
  end

  def root_for(id) do
    first_two = String.slice("#{id}", 0..1)
    Application.fetch_env!(:deutexrium, :data_path)
        |> Path.join(first_two)
        |> Path.join("#{id}")
  end
end
