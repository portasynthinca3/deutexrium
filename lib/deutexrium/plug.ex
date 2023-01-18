defmodule Deutexrium.Plug do
  import Plug.Conn
  use Plug.Router

  plug Deutexrium.Prometheus.Plug

  get "/metrics" do
    send_resp(conn, 200, "ok")
  end
end
