import Config

config :phoenix, :json_library, Jason

config :sprite_triage, SpriteTriageWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4090],
  pubsub_server: SpriteTriage.PubSub,
  live_view: [signing_salt: "sprite-triage"],
  render_errors: [formats: [html: SpriteTriageWeb.ErrorHTML], layout: false],
  check_origin: ["//localhost", "//127.0.0.1"],
  server: false

config :sprite_triage, web: true, access_key: nil

config :logger, level: :warning

import_config "#{config_env()}.exs"
