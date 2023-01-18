defmodule Deutexrium.Command.Generate do
  use Deutexrium.Command.WithDefaultImports
  @moduledoc """
  Generates a message using the channel's local model. Also handles training on
  / reacting to normal messages
  """

  require Logger

  def spec, do: %{
    name: "generate",
    flags: [:defer],
    options: [
      %{
        type: 4,
        name: "count",
        required: false
      }
    ]
  }

  def handle_command(%Struct.Interaction{locale: locale} = interaction) do
    id = {interaction.channel_id, interaction.guild_id}

    max_count = Server.Channel.get(id, :max_gen_len)
    count = case interaction.data.options do
      nil -> 1
      [%{name: "count", value: val}] when val >= 1 and val <= max_count -> val
      _ -> 0
    end

    content = if count > 0 do
      sentences = for _ <- 1..count, do: elem(Server.Channel.generate(id), 0)
      if :error in sentences do
        Logger.error("generation failed")
        translate(locale, "response.generate.gen_failed")
      else
        Enum.join(sentences, " ")
      end
    else
      translate(locale, "response.generate.val_too_big")
    end

    %{content: content}
  end

  def handle_other({:MESSAGE_CREATE, %Struct.Message{} = msg, _}) do
    self = msg.author.id == Nostrum.Cache.Me.get().id
    unless self or msg.guild_id == nil or msg.channel_id == nil do
      # react to mentions and replies
      bot_id = Nostrum.Cache.Me.get().id
      reference = Map.get(msg, :referenced_message, nil)
      ref_author = if reference, do: reference.author.id, else: nil
      ref_app = if reference, do: reference.application_id, else: nil
      bot_mentioned = String.contains?(msg.content, ["<@#{bot_id}>", "<@!#{bot_id}>"])
        or ref_author == bot_id
        or ref_app == bot_id

      if bot_mentioned do
        prompt = msg.content |> String.replace("<@#{bot_id}>", "") |> String.replace("<@!#{bot_id}>", "")
        Logger.debug("mentioned")
        {text, _} = Server.Channel.generate({msg.channel_id, msg.guild_id}, nil, prompt)
        Deutexrium.Util.Webhook.simulate_typing(text, msg.channel_id, false)
        Api.create_message(msg.channel_id, content: text, message_reference: %{message_id: msg.id})
      else
        # only train if it doesn't contain bot mentions
        case Server.Channel.handle_message(msg) do
          :ok -> :ok
          {:message, {text, author}} ->
            # see it it's impostor time
            impostor_rate = Server.Channel.get({msg.channel_id, msg.guild_id}, :impostor_rate)
            impostor_rate = if impostor_rate == nil, do: 0, else: impostor_rate
            webhook_data = if impostor_rate > 0 and :rand.uniform() <= impostor_rate / 100.0 do
                Server.Channel.get_meta({msg.channel_id, msg.guild_id}).webhook_data
            else
              nil
            end
            Deutexrium.Util.Webhook.try_sending_webhook({text, author}, msg.channel_id, webhook_data, msg.guild_id)
        end
      end
    end
  end

  def handle_other(_), do: :ok
end
