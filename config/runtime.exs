import Config

if config_env() != :test do
  # 127.0.0.1 unless SPRITE_TRIAGE_IP says otherwise (IPv4 or IPv6). Inside a container
  # use 0.0.0.0 and publish the port on the host's 127.0.0.1 only (see README).
  ip_text = System.get_env("SPRITE_TRIAGE_IP", "127.0.0.1")

  ip =
    case :inet.parse_address(String.to_charlist(ip_text)) do
      {:ok, ip} -> ip
      {:error, _} -> raise ArgumentError, "SPRITE_TRIAGE_IP must be an IP address, got #{ip_text}"
    end

  # Only for a hosted demo: the public host name, for URLs and the LiveView origin check.
  # On Fly.io it follows from the app name.
  host =
    case {System.get_env("SPRITE_TRIAGE_HOST"), System.get_env("FLY_APP_NAME")} do
      {nil, nil} -> nil
      {nil, app} -> app <> ".fly.dev"
      {host, _} -> host
    end

  # A hosted demo sets SECRET_KEY_BASE (a Fly secret), so sessions survive restarts and
  # work on every machine. Locally a fresh one per start is enough.
  config :sprite_triage, SpriteTriageWeb.Endpoint,
    secret_key_base:
      System.get_env("SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48)),
    server: System.get_env("SPRITE_TRIAGE_SERVER") == "true",
    http: [ip: ip, port: 4090]

  if host do
    config :sprite_triage, SpriteTriageWeb.Endpoint,
      url: [host: host, scheme: "https", port: 443],
      check_origin: ["https://" <> host]
  end

  # The token is read from the environment only and never rendered or written to disk.
  # SPRITE_TRIAGE_DEMO swaps the API for the simulated one.
  config :sprite_triage,
    demo: System.get_env("SPRITE_TRIAGE_DEMO") == "true",
    public_demo: System.get_env("SPRITE_TRIAGE_PUBLIC_DEMO") == "true",
    api_options: [token: System.get_env("SPRITES_TOKEN")]
end
