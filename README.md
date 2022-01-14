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
  - install InfluxDB v1.x and create a database named `deuterium`, it will be used to store stats
  - (optionally) install and configure Grafana to look at those stats
  - run `mix deps.get`
  - tweak self-explanatory settings in `config/config.exs` (optional)

### Running
Something like `DEUTEX_TOKEN=... iex -S mix`

### Exporting data from the master Deuterium instance
If you own a Discord server that you'd like to be served by a self-hosted instance of this bot and you have used this one before, you have the option of importing existing data. To do that, run the `/export` command of the master instance for both resource types (`channel` and `guild`). The three files you received should be placed in the `/var/deutex_data` directory on the machine that hosts your Deuterium instance (unless that path was changed in `config/config.exs`)

## Modification
If you're familiar with Elixir and OTP, take a look inside `/supervision_tree.txt` to learn more about its internal structure