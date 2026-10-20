defmodule SpriteTriageWeb.TriageLive do
  @moduledoc """
  One page: pick a Sprite, run the triage, read the next step, copy the note for support.

  Opening the page lists Sprites from the API only; no Sprite is woken. The page never
  restarts anything. The note can only be copied while it is fresh: a timer fires when
  the five minutes are up, and another one re-checks every 30 s.
  """
  use Phoenix.LiveView

  alias SpriteTriage.{Api, Note}
  alias SpriteTriageWeb.AccessKey

  @headline %{
    ok: "/check reports the Sprite as healthy",
    waking: "The Sprite is waking up",
    start_failed: "The machine behind this Sprite fails to start",
    storage_not_ready: "The Sprite's storage is not ready",
    control_only: "The Sprites API answers, the Sprite itself does not",
    unknown_network: "The Sprites API did not answer",
    unknown: "No clear picture",
    auth_error: "The token was rejected",
    not_found: "No Sprite with this name"
  }

  @impl true
  # A LiveView socket can be opened without the HTTP page; it needs the same session flag.
  def mount(_params, session, socket) when not is_map_key(session, "access_ok"),
    do: {:ok, assign(socket, denied: true)}

  # The session cookie is shared by every port on localhost, so a service on another
  # port could replay it. The connected socket therefore also needs the key itself,
  # which the page keeps in sessionStorage (scoped to this origin, port included).
  def mount(params, session, socket) do
    if connected?(socket) and not AccessKey.valid?(get_connect_params(socket)["key"]),
      do: {:ok, assign(socket, denied: true)},
      else: allowed_mount(params, session, socket)
  end

  defp allowed_mount(params, _session, socket) do
    socket =
      assign(socket,
        sprites: nil,
        list_error: nil,
        name: params["name"] || "",
        wake: false,
        report: nil,
        running: false,
        error: nil,
        demo: opts()[:plug] == SpriteTriage.Demo,
        token?: is_binary(opts()[:token]),
        denied: false,
        now: now()
      )

    socket =
      if connected?(socket) and socket.assigns.token? do
        :timer.send_interval(Application.get_env(:sprite_triage, :tick_ms, 30_000), :tick)
        start_async(socket, :list, fn -> Api.list(Api.new(opts()), 15_000) end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign(socket, now: now())}

  @impl true
  def handle_event(_event, _params, %{assigns: %{denied: true}} = socket), do: {:noreply, socket}

  # Keeps the checkbox (and name) in sync, so the list buttons can use it.
  def handle_event("form", params, socket),
    do: {:noreply, assign(socket, wake: params["wake"] == "true", name: params["name"] || "")}

  def handle_event("triage", _params, %{assigns: %{running: true}} = socket),
    do: {:noreply, socket}

  def handle_event("triage", _params, %{assigns: %{token?: false}} = socket),
    do: {:noreply, socket}

  # The list buttons send only a name; they use the checkbox as it is on the form.
  def handle_event("triage", params, socket) do
    name = String.trim(params["name"] || "")
    wake = if params["source"] == "list", do: socket.assigns.wake, else: params["wake"] == "true"

    if name == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(name: name, wake: wake, running: true, report: nil, error: nil)
       |> start_async(:triage, fn -> SpriteTriage.triage(name, opts() ++ [wake: wake]) end)}
    end
  end

  @impl true
  def handle_async(:list, {:ok, %{outcome: :ok, body: %{"sprites" => sprites}}}, socket),
    do: {:noreply, assign(socket, sprites: sprites)}

  def handle_async(:list, {:ok, obs}, socket),
    do:
      {:noreply,
       assign(socket, list_error: "Could not list Sprites (#{obs.http_status || obs.outcome}).")}

  def handle_async(:list, {:exit, _}, socket),
    do: {:noreply, assign(socket, list_error: "Could not list Sprites.")}

  # Besides the periodic tick, one tick exactly when the note goes stale.
  def handle_async(:triage, {:ok, report}, socket) do
    left = Note.ms_left(report, now())
    if left > 0, do: Process.send_after(self(), :tick, left)
    {:noreply, assign(socket, report: report, running: false, now: now())}
  end

  # The reason may contain request details; it stays in the server log.
  def handle_async(:triage, {:exit, reason}, socket) do
    require Logger
    Logger.error("triage crashed: #{inspect(reason)}")
    {:noreply, assign(socket, running: false, error: "The triage crashed; see the server log.")}
  end

  defp opts, do: Application.get_env(:sprite_triage, :api_options, [])
  defp now, do: Application.get_env(:sprite_triage, :clock, &DateTime.utc_now/0).()

  defp stale?(report, now), do: Note.stale?(report, now)

  defp headline(state), do: Map.get(@headline, state, "Unknown state")

  # The first step that is an action, not housekeeping.
  defp next_step(report),
    do:
      Enum.find(
        report.advice.do,
        hd(report.advice.do),
        &(&1.id not in [:stop_traffic, :keep_note])
      )

  # With a single step the box says it all; the list would only repeat it.
  defp single_step?(report), do: length(report.advice.do) == 1

  @impl true
  def render(%{denied: true} = assigns) do
    ~H"""
    <main class="page"><p>Open the address that sprite-triage printed when it started.</p></main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="page">
      <p :if={@demo} id="demo-banner" class="demo">
        Demo mode: a simulated Sprites API replays patterns from public forum threads and from our own measurements. Nothing is sent to Fly.
      </p>
      <header class="top">
        <h1>sprite-triage</h1>
        <p>
          For a Sprite that stopped answering: what the signals say, what to do next, and a short note for Fly support.
          It only reads; it never restarts or changes a Sprite.
        </p>
      </header>

      <section class="pick" aria-labelledby="pick-h">
        <h2 id="pick-h">Sprite</h2>
        <form id="triage-form" phx-submit="triage" phx-change="form">
          <label for="name">Name</label>
          <input id="name" name="name" value={@name} autocomplete="off" required />
          <label class="check">
            <input type="checkbox" name="wake" value="true" checked={@wake} /> Also run <code>true</code> inside the Sprite (wakes it)
          </label>
          <button type="submit" disabled={@running}>{if @running, do: "Checking…", else: "Run triage"}</button>
        </form>
        <p class="hint">
          Triage reads the Sprites API and calls <code>/check</code>, which may wake the Sprite.
          Commands run inside the Sprite only if you tick the box.
        </p>
        <p :if={@error} class="error" role="alert">{@error}</p>
        <p :if={!@token?} id="no-token" class="error" role="alert">
          SPRITES_TOKEN is not set. Start the page with the token in the environment.
        </p>
      </section>

      <section id="result" aria-live="polite" aria-labelledby={@report && "result-h"}>
        <div :if={@report} id="report" phx-hook="Reveal">
          <h2 id="result-h" tabindex="-1" class={"state state-#{@report.classification.state}"}>
            {headline(@report.classification.state)}
          </h2>
          <p class="reason">{@report.name}: {@report.classification.reason}</p>

          <div :if={@report.classification.state != :ok} id="next-step" class="next">
            <strong>Next step:</strong> {next_step(@report).text}
            <span :if={single_step?(@report)} class="sources">
              Source: <.links urls={next_step(@report).sources} />
            </span>
          </div>

          <h3 :if={not single_step?(@report)}>Do</h3>
          <ol :if={not single_step?(@report)} id="do">
            <li :for={s <- @report.advice.do}>
              {s.text}
              <span class="sources">
                Source: <.links urls={s.sources} />
                <span :if={s.counter_sources != []}>· did not help in: <.links urls={s.counter_sources} /></span>
              </span>
            </li>
          </ol>

          <h3 :if={@report.advice.dont != []}>Don't</h3>
          <ul :if={@report.advice.dont != []} id="dont">
            <li :for={s <- @report.advice.dont}>
              {s.text} <span class="sources">Source: <.links urls={s.sources} /></span>
            </li>
          </ul>

          <div :if={@report.note}>
            <h3>Note for Fly support</h3>
            <pre id="note">{@report.note}</pre>
            <p :if={stale?(@report, @now)} id="stale" class="error">
              This note is older than five minutes. Run the triage again before sending it.
            </p>
            <button :if={!stale?(@report, @now)} id="copy-note" phx-hook="CopyNote" data-target="note">
              Copy note
            </button>
          </div>

          <details id="checked">
            <summary>What was checked</summary>
            <p :if={@report.woke_sprite} class="hint">This triage called <code>/check</code>, which may have woken the Sprite.</p>
            <table id="observations">
              <thead><tr><th>Probe</th><th>Result</th><th>Time</th><th>fly-request-id</th></tr></thead>
              <tbody>
                <tr :for={o <- @report.observations}>
                  <td>{o.probe}</td>
                  <td>{result_text(o)}</td>
                  <td>{if o.elapsed_ms, do: "#{o.elapsed_ms} ms", else: "–"}</td>
                  <td><code>{o.request_id || "–"}</code></td>
                </tr>
              </tbody>
            </table>
          </details>
        </div>
      </section>

      <section aria-labelledby="list-h">
        <h2 id="list-h">Sprites in this organization</h2>
        <p :if={@list_error} class="error">{@list_error}</p>
        <table :if={@sprites} id="sprites">
          <thead><tr><th>Name</th><th>Reported status</th><th></th></tr></thead>
          <tbody>
            <tr :for={s <- @sprites} id={"sprite-" <> s["name"]}>
              <td>{s["name"]}</td>
              <td>{s["status"]}</td>
              <td>
                <button
                  phx-click="triage"
                  phx-value-name={s["name"]}
                  phx-value-source="list"
                  disabled={@running}
                  aria-label={"Triage " <> s["name"]}
                >
                  Triage
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@sprites} class="hint">
          The reported status is the API's label, not a health signal: unreachable Sprites have shown all three values.
        </p>
      </section>
    </main>
    """
  end

  defp links(assigns) do
    ~H"""
    <span :for={{u, i} <- Enum.with_index(@urls)}><span :if={i > 0}>, </span><.source url={u} /></span>
    """
  end

  defp source(%{url: "http" <> _} = assigns), do: ~H|<a href={@url}>{short(@url)}</a>|
  defp source(assigns), do: ~H|<span>{@url}</span>|

  defp result_text(%{outcome: :ok, http_status: s, body: %{"status" => st}}) when is_binary(st),
    do: "#{s} · #{st}"

  defp result_text(%{outcome: :ok, http_status: s}), do: "#{s || "ok"}"
  defp result_text(%{outcome: :http_error, http_status: s} = o), do: "HTTP #{s} #{short_body(o)}"
  defp result_text(%{outcome: :timeout}), do: "no answer before the deadline"
  defp result_text(%{outcome: :transport_error, error: e}), do: "connection failed: #{e}"

  defp short_body(%{body: b}) when is_binary(b), do: String.slice(b, 0, 80)
  defp short_body(%{body: %{"error" => e}}), do: e
  defp short_body(_), do: ""

  defp short("https://community.fly.io/t/" <> id), do: "forum #{id}"
  defp short("https://github.com/superfly/sprites-docs/issues/" <> id), do: "sprites-docs##{id}"
  defp short("https://fly.io/dashboard/support"), do: "Fly support"
  defp short(url), do: URI.parse(url).host
end
