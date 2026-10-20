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

  # Set only for a hosted demo (fly.toml): the public host name, for URLs and the
  # LiveView origin check.
  host = System.get_env("SPRITE_TRIAGE_HOST")

  config :sprite_triage, SpriteTriageWeb.Endpoint,
    secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48)),
    server: System.get_env("SPRITE_TRIAGE_SERVER") == "true",
    http: [ip: ip, port: 4090]

  if host do
    config :sprite_triage, SpriteTriageWeb.Endpoint,
      url: [host: host, scheme: "https", port: 443],
      check_origin: ["https://" <> host]
  end

  # The token is read from the environment only and never rendered or written to disk.
  # A fresh key per start unless one is given (checked in AccessKey.setup!/0); it is
  # printed with the URL.
  config :sprite_triage,
    access_key: System.get_env("SPRITE_TRIAGE_KEY"),
    public_demo: System.get_env("SPRITE_TRIAGE_PUBLIC_DEMO") == "true",
    api_options: [token: System.get_env("SPRITES_TOKEN")],
    data_dir: System.get_env("SPRITE_TRIAGE_DATA", Path.expand("~/.sprite-triage"))
end
