defmodule SpriteTriageWeb.TriageLive do
  @moduledoc """
  One page: pick a Sprite, run the triage, read the next step, copy the note for support.

  Opening the page lists Sprites from the API only; no Sprite is woken. The page never
  restarts anything. The note can only be copied while it is fresh; a timer re-checks
  its age every 30 s.
  """
  use Phoenix.LiveView
  require Logger

  alias SpriteTriage.{Api, Note}

  @headline %{
    ok: "The Sprite answers",
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

  def mount(params, _session, socket) do
    socket =
      assign(socket,
        sprites: nil,
        list_error: nil,
        name: params["name"] || "",
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

  def handle_event("triage", _params, %{assigns: %{running: true}} = socket),
    do: {:noreply, socket}

  def handle_event("triage", _params, %{assigns: %{token?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("triage", params, socket) do
    name = String.trim(params["name"] || "")

    if name == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(name: name, running: true, report: nil, error: nil)
       |> start_async(:triage, fn -> SpriteTriage.triage(name, opts()) end)}
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

  def handle_async(:triage, {:ok, report}, socket),
    do: {:noreply, assign(socket, report: report, running: false, now: now())}

  # The reason may contain request details; it stays in the server log.
  def handle_async(:triage, {:exit, reason}, socket) do
    Logger.error("triage crashed: #{inspect(reason)}")
    {:noreply, assign(socket, running: false, error: "The triage crashed; see the server log.")}
  end

  defp opts, do: Application.get_env(:sprite_triage, :api_options, [])
  defp now, do: Application.get_env(:sprite_triage, :clock, &DateTime.utc_now/0).()

  defp stale?(report, now), do: Note.stale?(report, now)

  defp headline(state), do: Map.get(@headline, state, "Unknown state")

  # The first step is shown in its own box, the rest below it in their order.
  defp next_step(report), do: hd(report.advice.do)
  defp other_steps(report), do: tl(report.advice.do)

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
          It restarts nothing and changes no settings; the checks below can wake the Sprite.
        </p>
      </header>

      <section class="pick" aria-labelledby="pick-h">
        <h2 id="pick-h">Sprite</h2>
        <form id="triage-form" phx-submit="triage">
          <label for="name">Name</label>
          <input id="name" name="name" value={@name} autocomplete="off" required />
          <button type="submit" disabled={@running}>{if @running, do: "Checking…", else: "Run triage"}</button>
        </form>
        <p :if={@running} id="running" class="hint" role="status">
          Waiting for the Sprite: up to a minute for <code>/check</code>, then up to 45 s for the command.
        </p>
        <p class="hint">
          Triage reads the Sprites API and calls <code>/check</code>. When <code>/check</code> answers,
          it runs <code>true</code> inside the Sprite once. Both can wake a sleeping Sprite.
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

          <div id="next-step" class="next">
            <strong>Next step:</strong> {next_step(@report).text}
            <.step_sources step={next_step(@report)} />
          </div>

          <h3 :if={other_steps(@report) != []}>Also</h3>
          <ol :if={other_steps(@report) != []} id="do">
            <li :for={s <- other_steps(@report)}>
              {s.text} <.step_sources step={s} />
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

  defp step_sources(assigns) do
    ~H"""
    <span class="sources">
      Source: <.links urls={@step.sources} />
      <span :if={@step.counter_sources != []}>· did not help in: <.links urls={@step.counter_sources} /></span>
    </span>
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
