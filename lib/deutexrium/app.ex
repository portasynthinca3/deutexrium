defmodule Deutexrium.App do
  @moduledoc """
  Deutexrium OTP app
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Data path: #{Application.fetch_env!(:deutexrium, :data_path)}")
    Deutexrium.Sup.start_link([])
  end
end
