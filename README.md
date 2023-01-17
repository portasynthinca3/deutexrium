# Deutexrium
[![Discord Bots](https://top.gg/api/widget/owner/733605243396554813.svg)](https://top.gg/bot/733605243396554813)
[![Discord Bots](https://top.gg/api/widget/status/733605243396554813.svg)](https://top.gg/bot/733605243396554813)

Elixir [Deuterium](https://github.com/portasynthinca3/deuterium) rewrite, a Discord bot that automatically generates messages based on the previously seen ones on a per-channel basis.

## Use an existing one
[Invite it to your server](https://discord.com/oauth2/authorize?client_id=733605243396554813&scope=bot%20applications.commands)

## Run your own
Please note that Deuterium uses a [custom permissive license](LICENSE.md). It's only 6 lines long and it's a good idea to read it!

This app is dockerized, so it can be deployed in a few simple steps:
  1. Create the data volume: `docker volume create --driver local --opt type=none --opt device=/path/on/the/host/where/data/will/be/stored --opt o=bind deut_data`
  2. Save your Discord bot token: `printf "DEUTEX_TOKEN=Y0uЯ-t0k3n" > .env`
  3. Pull the image: `docker pull ghcr.io/portasynthinca3/deutexrium:latest`
  4. Run the container: `docker run --mount source=deut_data,target=/var/deutexrium --env-file .env -d deutexrium`

To connect an IEx shell to a locally running container:
  1. Download `epmd_docker`: `git clone https://github.com/rlipscombe/epmd_docker.git && cd epmd_docker`
  2. Build `epmd_docker`: `make`
  3. Run `docker ps` and find out the ID of the container
  4. Run `iex --erl "-pa ebin -epmd_module epmd_docker -setcookie deutexrium -sname shell" --remsh deuterium@c0nta1ner-1d`

On first startup and when updating the bot register slash commands using the shell (one of):
  * `Ctl.add_slash_commands` to register them globally (takes about an hour to update across all servers)
  * `Ctl.add_slash_commands(123)` to register them in the Discord server with ID 123 (instant)

### Exporting data from the master Deuterium instance
Contact me (`/support`) to get your data package. I'm working on a solution to download the data without human intervention just like Deuterium 1.x has previously allowed.

## TODO
  - bring back `/forget`
  - bring back `/export`
  - refactor the settings server (literal unreadable code atm)
  - set up a Weblate instance for translation
