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
