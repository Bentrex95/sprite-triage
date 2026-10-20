import Config

config :sprite_triage, SpriteTriageWeb.Endpoint,
  secret_key_base: String.duplicate("test-only-not-a-secret-", 4),
  server: false

config :sprite_triage,
  tick_ms: 50,
  access_key: "test-key-0123456789",
  api_options: [
    token: "test-token",
    plug: {Req.Test, SpriteTriage.ApiStub},
    deadlines: [sprite: 300, check: 300, exec: 300]
  ]
