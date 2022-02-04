defmodule Deutexrium.App do
  @moduledoc """
  Deutexrium OTP app
  """

  use Application

  @impl true
  def start(_type, _args) do
    Deutexrium.Sup.start_link([])
  end
end
