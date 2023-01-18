import Config

config :deutexrium,
  data_path: "/var/deutexrium/data",
  channel_unload_timeout: 3 * 1000, # milliseconds
  guild_unload_timeout: 4 * 1000,
  log_interval: 2000,
  node_voice_server: {'localhost', 2700},
  pre_train_batch_size: 100

# assuming InfluxDB v1.x
# refer to https://github.com/mneudert/instream#usage for v2 config examples
config :deutexrium, Deutexrium.Influx,
  auth: [username: "admin", password: "admin"],
  database: "deuterium",
  host: "localhost"

config :logger,
  level: :debug,
  backends: [:console, {LoggerFileBackend, :file}]
config :logger, :console,
  metadata: [:shard, :guild, :channel],
  level: :info
config :logger, :file,
  path: "/var/deutexrium/latest.log",
  level: :info

config :nostrum,
  num_shards: :auto,
  gateway_intents: [
    :guilds,
    :guild_messages,
    :message_content
  ]
