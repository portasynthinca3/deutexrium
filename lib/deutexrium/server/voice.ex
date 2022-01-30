defmodule Deutexrium.Server.Voice do
  use GenServer
  require Logger
  alias Deutexrium.Server.{RqRouter, Channel}

  @impl true
  def init(id={chan, _}) do
    # create websocket connection to Node voice server
    {host, port} = Application.fetch_env!(:deutexrium, :node_voice_server)
    {:ok, conn} = :gun.open(host, port)
    stream = :gun.ws_upgrade(conn, "/")
    # tell it the channel id
    :gun.ws_send(conn, stream, {:text, Jason.encode!(%{
      op: "connect",
      lang: "ru",
      id: "#{chan}"
    })})

    timeout = Application.fetch_env!(:deutexrium, :guild_unload_timeout)
    {:ok, {id, timeout, {conn, stream}}, timeout}
  end

  @impl true
  def handle_call(:join, _, state={_, timeout, _}) do
    {:reply, :ok, state, timeout}
  end

  @impl true
  def handle_info(:timeout, _) do
    exit(:normal)
  end

  @impl true
  def handle_info({:gun_ws, _, _, {:text, json}}, state={id, timeout, _}) do
    data = Jason.decode!(json) |> Enum.into(%{})
    if data |> Map.get("op") == "recognized" do
      text = data |> Map.get("text") |> IO.inspect
      unless text == "" do
        if text in ["slash say", "slash generate", "бот скажи", "вот скажи"] do
          # if text is "/say" or "/generate, don't train
          {_, _, text} = Channel.generate(id)
          send(self(), {:say, text})
        else
          user = data |> Map.get("user") |> :erlang.binary_to_integer
          case Channel.handle_message(id, text, false, user) do
            :ok -> :ok
            {:message, {_, _, text}} -> send(self(), {:say, text})
          end
        end
      end
    end
    {:noreply, state, timeout}
  end

  @impl true
  def handle_info({:say, text}, state={_, timeout, {conn, stream}}) do
    :gun.ws_send(conn, stream, {:text, Jason.encode!(%{
      op: "say",
      text: text
    })})
    {:noreply, state, timeout}
  end

  @impl true
  def handle_info(_, state={_, timeout, _}) do
    {:noreply, state, timeout}
  end


  # ===== API =====


  @type server_id() :: {integer(), integer()}

  @spec join(server_id()) :: :ok
  def join(id) when (is_integer(id) or is_tuple(id)) do
    id |> RqRouter.route_to_voice(:join)
  end
end
