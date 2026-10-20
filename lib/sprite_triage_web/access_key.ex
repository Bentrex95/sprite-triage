defmodule SpriteTriageWeb.AccessKey do
  @moduledoc """
  The page acts with the owner's token, so it listens on 127.0.0.1 and needs a random key
  that is printed with the URL at start (like a notebook server). The first visit with
  `?key=…` marks the browser session; requests without that session get 403, and the
  LiveView socket needs the same session.
  """
  import Plug.Conn

  @session_key "access_ok"

  def key, do: Application.fetch_env!(:sprite_triage, :access_key)

  def url, do: "http://localhost:4090/?key=#{key()}"

  @doc """
  A public demo (`SPRITE_TRIAGE_PUBLIC_DEMO=true`) needs no key. Only possible against
  the simulated API, where there is no real token to protect; see `setup!/0`.
  """
  def open?,
    do: Application.get_env(:sprite_triage, :public_demo, false) == true and demo_api?()

  defp demo_api?,
    do:
      Keyword.get(Application.get_env(:sprite_triage, :api_options, []), :plug) ==
        SpriteTriage.Demo

  @doc "Makes a random key at start (tests set a fixed one) and refuses an open page with a real token."
  def setup! do
    if Application.get_env(:sprite_triage, :public_demo, false) == true and not demo_api?(),
      do:
        raise(ArgumentError, "SPRITE_TRIAGE_PUBLIC_DEMO only works with SPRITE_TRIAGE_DEMO=true")

    unless Application.get_env(:sprite_triage, :access_key),
      do:
        Application.put_env(
          :sprite_triage,
          :access_key,
          Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
        )
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    given = conn.query_params["key"]

    cond do
      get_session(conn, @session_key) == true ->
        conn

      open?() ->
        put_session(conn, @session_key, true)

      is_binary(given) and Plug.Crypto.secure_compare(given, key()) ->
        conn
        |> put_session(@session_key, true)
        |> put_resp_header("referrer-policy", "no-referrer")
        |> put_resp_header("cache-control", "no-store")

      true ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          403,
          "Open the address that sprite-triage printed when it started (it contains ?key=…)."
        )
        |> halt()
    end
  end
end
