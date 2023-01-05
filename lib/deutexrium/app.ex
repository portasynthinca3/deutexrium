defmodule Deutexrium.App do
  @moduledoc """
  Deutexrium OTP app
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    dir = Application.fetch_env!(:deutexrium, :data_path)
    Logger.info("Data path: #{dir}")

    :mnesia.wait_for_tables([
      Markov.Database.Link,
      Markov.Database.Master,
      Markov.Database.Operation
    ], 5000)

    Deutexrium.Sup.start_link([])
  end
end
