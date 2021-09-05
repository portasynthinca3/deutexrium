use Mix.Config

config :deutexrium,
  data_path: "/var/deutex_data",
  channel_unload_timeout: 60 * 1000, # milliseconds
  guild_unload_timeout: 3 * 60 * 1000

config :logger,
  level: :debug,
  backends: [:console, {LoggerFileBackend, :debug_log}]
config :logger, :console,
  metadata: [:shard, :guild, :channel]
config :logger, :debug_log,
  path: "deuterium.log",
  level: :debug

config :nostrum,
  token: System.get_env("DEUTEX_TOKEN"),
  num_shards: :auto

config :porcelain,
  goon_warn_if_missing: false
