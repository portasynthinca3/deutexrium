use Mix.Config

config :logger,
  level: :debug

config :logger, :console,
  metadata: [:shard, :guild, :channel]

config :nostrum,
  token: System.get_env("DEUTEX_TOKEN"),
  num_shards: :auto

config :porcelain,
  goon_warn_if_missing: false

config :deutexrium,
  data_path: "/var/deutex_data",
  channel_unload_timeout: 10 * 60 * 1000, # milliseconds
  guild_unload_timeout: 7 * 24 * 3600 * 1000
