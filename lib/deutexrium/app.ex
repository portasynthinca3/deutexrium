defmodule Deutexrium.App do
  use Application
  @moduledoc """
  Deutexrium OTP app
  """

  @impl true
  def start(_type, _args) do
    dir = Application.fetch_env!(:deutexrium, :data_path)
    File.mkdir_p(dir |> Path.join("data"))

    Deutexrium.Sup.start_link([])
  end
end
