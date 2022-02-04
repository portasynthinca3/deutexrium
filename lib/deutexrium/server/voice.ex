defmodule Deutexrium.Server.Voice do
  @moduledoc """
  Communicates with the Node Voice Server:
    - gets recognized sentences from it
    - asks it to say things
  """

  use GenServer
  require Logger
  alias Deutexrium.Server.{RqRouter, Channel}

  @triggers [
    "slash say",
    "slash generate",
    "бот скажи",
    "вот скажи",
  ]
  defp is_trigger(alts), do:
    alts |> Enum.any?(fn %{"text" => text} -> text in @triggers end)

  @impl true
  def init(id) do
    # create http connection
    {host, port} = Application.fetch_env!(:deutexrium, :node_voice_server)
    {:ok, conn} = :gun.open(host, port)
    receive do
      {:gun_up, ^conn, _} -> :ok
    end

    # upgrade to websocket
    stream = :gun.ws_upgrade(conn, "/")
    receive do
      {:gun_upgrade, ^conn, ^stream, _, _} -> :ok
    end

    # set generation rate
    Deutexrium.Server.Channel.set(id, :autogen_rate, 15)

    timeout = Application.fetch_env!(:deutexrium, :channel_unload_timeout)
    {:ok, {id, timeout, {conn, stream}}, timeout}
  end

  @impl true
  def handle_call({:join, lang}, _, state={{chan, _}, timeout, {conn, stream}}) do
    # tell it the channel id
    :gun.ws_send(conn, stream, {:text, Jason.encode!(%{
      op: "connect",
      lang: lang,
      id: "#{chan}"
    })})
    Logger.info("voice-#{chan}: connected to vc")

    {:reply, :ok, state, timeout}
  end

  @impl true
  def handle_info(:timeout, {_, _, {conn, stream}}) do
    :gun.ws_send(conn, stream, {:text, Jason.encode!(%{
      op: "disconnect"
    })})
    exit(:normal)
  end

  @impl true
  def handle_info({:gun_ws, _, _, {:text, json}}, state={id={chan, _}, timeout, _}) do
    %{"op" => op} = data = Jason.decode!(json) |> Enum.into(%{})

    case op do
      "recognized" ->
        text = data |> Map.get("result") |> Map.get("text")
        alternatives = data |> Map.get("result") |> Map.get("alternatives")

        # process text
        unless text == "" do
          if is_trigger(alternatives) do
            # if text is a trigger
            {_, _, text} = Channel.generate(id)
            Logger.info("voice-#{chan}: trigger seq")
            send(self(), {:say, text})
          else
            user = data |> Map.get("user") |> :erlang.binary_to_integer
            case Channel.handle_message(id, text, false, user) do
              :ok -> :ok
              {:message, {_, _, text}} -> send(self(), {:say, text})
            end
          end
        end
        {:noreply, state, timeout}

      "disconnected" ->
        {:stop, :voice_down, state}
    end
  end

  @impl true
  def handle_info({:gun_down, _, _, :closed, _}, state) do
    {:stop, :voice_down, state}
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

  @spec join(server_id(), String.t()) :: :ok
  def join(id, lang) when (is_integer(id) or is_tuple(id)) and is_binary(lang) do
    id |> RqRouter.route_to_voice({:join, lang})
  end
end
