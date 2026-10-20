defmodule SpriteTriageWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sprite_triage

  @session_options [
    store: :cookie,
    key: "_sprite_triage",
    signing_salt: "triage",
    same_site: "Strict"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  # Phoenix and LiveView ship their browser modules; serve them straight from the deps.
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"}, gzip: false)

  plug(Plug.Static,
    at: "/vendor/live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false
  )

  plug(Plug.Static, at: "/assets", from: {:sprite_triage, "priv/static/assets"}, gzip: false)
  plug(Plug.RequestId)
  plug(Plug.Parsers, parsers: [:urlencoded], pass: [], length: 64_000)
  plug(Plug.Session, @session_options)
  plug(SpriteTriageWeb.Router)
end

defmodule SpriteTriageWeb.ErrorHTML do
  def render(_template, _assigns), do: "Request could not be handled."
end
