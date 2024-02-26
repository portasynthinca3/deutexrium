import Config

config :nostrum,
  token: System.get_env("DEUTEX_TOKEN") |> String.trim
