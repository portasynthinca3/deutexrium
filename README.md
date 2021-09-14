# Deutexrium
[![Discord Bots](https://top.gg/api/widget/owner/733605243396554813.svg)](https://top.gg/bot/733605243396554813)
[![Discord Bots](https://top.gg/api/widget/servers/733605243396554813.svg)](https://top.gg/bot/733605243396554813)
[![Discord Bots](https://top.gg/api/widget/status/733605243396554813.svg)](https://top.gg/bot/733605243396554813)

Elixir [Deuterium](https://github.com/portasynthinca3/deuterium) rewrite, a Discord bot that automatically generates messages based on the previously seen ones on a per-channel basis.

## Use an existing one
[Just invite it to your server](https://discord.com/oauth2/authorize?client_id=733605243396554813&scope=bot%20applications.commands)

## Run your own

### Setting up
  - install Elixir and Mix
  - run `mix deps.get`
  - tweak self-explanatory settings in `config/config.exs` (optional)

### Running
Something like `DEUTEX_TOKEN=... iex -S mix`

### Usage notice
If you integrate this bot's functionality into your own bot, or even just straight up copy it, you must credit me (portasynthinca3) as the creator of the original software. You may not change or remove the link mentioned in the response of `/donate`, however you might add your own.

## Modification
If you're familiar with Elixir and OTP, take a look inside `/supervision_tree.txt` to learn more about its internal structure