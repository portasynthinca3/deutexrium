import Config

config :deutexrium,
  data_path: (if config_env() == :prod, do: "/var/deutex_data", else: "/var/deutex_test"),
  channel_unload_timeout: 3 * 60 * 1000, # milliseconds
  guild_unload_timeout: 4 * 60 * 1000,
  debug_people: [471715557096554518], # ids of people that can run "deut_debug"
  default_router_cnt: 4,
  log_interval: 2000,
  node_voice_server: {'localhost', 2700}

# assuming InfluxDB v1.x
# refer to https://github.com/mneudert/instream#usage for v2 config examples
config :deutexrium, Deutexrium.Influx,
  auth: [username: "admin", password: "admin"],
  database: "deuterium",
  host: "localhost"

config :logger,
  level: :debug,
  backends: [:console, {LoggerFileBackend, :debug_log}]
config :logger, :console,
  metadata: [:shard, :guild, :channel],
  level: (if config_env() == :prod, do: :notice, else: :info)
config :logger, :debug_log,
  path: "deuterium.log",
  level: :info

config :nostrum,
  token: System.get_env("DEUTEX_TOKEN"),
  num_shards: :auto,
  gateway_intents: [
    :guilds,
    :guild_messages,
    :message_content
  ]

config :graceful_stop, :hooks, [
  [Ctl, :shutdown, []]
]
