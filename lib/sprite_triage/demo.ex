defmodule SpriteTriage.Demo do
  @moduledoc """
  A simulated Sprites API for trying the tool without an account. Each Sprite name
  replays a pattern from the public forum threads or from our own measurements on real
  Sprites; nothing here talks to Fly.

    * `demo-healthy`       – reported `cold`, /check healthy (28288)
    * `demo-waking`        – /check answers "needs_repair: machine in suspended state", as
                             real Sprites did on every first wake after a quiet period;
                             a command inside runs fine (own measurements)
    * `demo-wedged`        – /check healthy, but a command inside hangs (28561, sprites-docs#230);
                             only visible with the exec probe
    * `demo-storage`       – /check answers 503 "Storage not ready" (28785, 28835)
    * `demo-start-failed`  – /check unhealthy, "failed to start machine" (28696)
  """

  @behaviour Plug
  import Plug.Conn

  def sprites, do: ~w(demo-healthy demo-waking demo-wedged demo-storage demo-start-failed)

  def api_options do
    [
      token: "demo",
      plug: __MODULE__,
      deadlines: [sprite: 3_000, check: 4_000, exec: 4_000],
      spawn: &spawn_command/2
    ]
  end

  @doc false
  # Stands in for Sprites.spawn/3, so the real exec guard runs: a wedged Sprite's
  # command never exits and has to be killed at the deadline.
  def spawn_command("demo-wedged", _opts),
    do: {:ok, %{ref: make_ref(), pid: spawn(fn -> Process.sleep(:infinity) end)}}

  def spawn_command(_name, _opts) do
    ref = make_ref()
    send(self(), {:exit, %{ref: ref}, 0})
    {:ok, %{ref: ref, pid: spawn(fn -> :ok end)}}
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "GET", request_path: "/v1/sprites"} = conn, _) do
    json(conn, 200, %{"sprites" => Enum.map(sprites(), &sprite/1)})
  end

  def call(%{method: "GET", request_path: "/v1/sprites/" <> rest} = conn, _) do
    case String.split(rest, "/") do
      [name] ->
        if name in sprites(),
          do: json(conn, 200, sprite(name)),
          else: json(conn, 404, %{"error" => "not found"})

      [name, "check"] ->
        check(conn, name)

      _ ->
        json(conn, 404, %{"error" => "not found"})
    end
  end

  def call(conn, _), do: json(conn, 404, %{"error" => "not found"})

  defp sprite(name) do
    %{
      "id" => "sprite-0000demo-" <> String.replace_prefix(name, "demo-", ""),
      "name" => name,
      "organization" => "demo-org",
      "status" => if(name == "demo-wedged", do: "warm", else: "cold")
    }
  end

  defp check(conn, "demo-healthy"), do: json(conn, 200, %{"status" => "healthy"})

  # The body a real Sprite returned on its first /check after 15 quiet minutes.
  defp check(conn, "demo-waking"),
    do:
      json(conn, 200, %{
        "status" => "needs_repair",
        "reason" => "machine in suspended state",
        "elapsed" => 100
      })

  defp check(conn, "demo-wedged"), do: json(conn, 200, %{"status" => "healthy"})
  defp check(conn, "demo-storage"), do: text(conn, 503, "Storage not ready")

  defp check(conn, "demo-start-failed"),
    do: json(conn, 200, %{"status" => "unhealthy", "reason" => "failed to start machine"})

  defp check(conn, _), do: json(conn, 404, %{"error" => "not found"})

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("fly-request-id", "01DEMO" <> Base.encode32(:crypto.strong_rand_bytes(5)))
    |> send_resp(status, Jason.encode!(body))
  end

  defp text(conn, status, body) do
    conn
    |> put_resp_header("fly-request-id", "01DEMO" <> Base.encode32(:crypto.strong_rand_bytes(5)))
    |> send_resp(status, body)
  end
end
