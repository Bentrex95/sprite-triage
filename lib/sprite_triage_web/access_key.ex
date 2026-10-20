defmodule SpriteTriageWeb.AccessKey do
  @moduledoc """
  The page acts with the owner's token, so binding to 127.0.0.1 is not enough on a
  machine with other local users. A random key is made at start and printed with the
  URL (like a notebook server).

  Two checks use it:

    * HTTP: the first visit with `?key=…` marks the browser session; any other request
      without that session gets 403.
    * LiveView socket: the session alone is not enough, because the cookie is shared by
      every port on localhost and a service on another port could replay it. The page
      keeps the key in sessionStorage (scoped to origin *and* port), takes it out of the
      address bar, and sends it when the socket connects (see `priv/static/assets/app.js`).
  """
  import Plug.Conn

  @session_key "access_ok"
  @min_length 16

  def session_key, do: @session_key

  def key, do: Application.fetch_env!(:sprite_triage, :access_key)

  def url,
    do: if(open?(), do: "http://localhost:4090/", else: "http://localhost:4090/?key=#{key()}")

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

  @doc "Whether `given` is the key. Constant-time comparison."
  def valid?(given) when is_binary(given), do: open?() or Plug.Crypto.secure_compare(given, key())
  def valid?(_), do: open?()

  @doc """
  Fixes the key at start: a configured key (`SPRITE_TRIAGE_KEY`) is used if it has at
  least #{@min_length} characters, a blank one counts as unset, and an unset one is
  replaced by a random key. A shorter key stops the start.
  """
  def setup! do
    if Application.get_env(:sprite_triage, :public_demo, false) == true and not demo_api?(),
      do:
        raise(ArgumentError, "SPRITE_TRIAGE_PUBLIC_DEMO only works with SPRITE_TRIAGE_DEMO=true")

    key =
      case Application.get_env(:sprite_triage, :access_key) do
        k when k in [nil, ""] ->
          Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

        k when is_binary(k) ->
          # Only characters that survive a URL unchanged, so the printed address works.
          if k =~ ~r/\A[A-Za-z0-9_-]{#{@min_length},}\z/,
            do: k,
            else:
              raise(
                ArgumentError,
                "SPRITE_TRIAGE_KEY must be at least #{@min_length} characters of A-Z, a-z, 0-9, _ and -"
              )
      end

    Application.put_env(:sprite_triage, :access_key, key)
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    cond do
      get_session(conn, @session_key) == true ->
        conn

      open?() ->
        put_session(conn, @session_key, true)

      valid?(conn.query_params["key"]) ->
        # The page itself removes the key from the address bar (history.replaceState),
        # after putting it into sessionStorage for the socket.
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
