defmodule SpriteTriageWeb.LiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias SpriteTriage.Stubs

  @endpoint SpriteTriageWeb.Endpoint

  # A browser session that has passed the access key.
  defp conn, do: build_conn() |> Plug.Test.init_test_session(%{"access_ok" => true})

  # Opens the page and waits for the Sprite list started at mount, so no test races it.
  defp open_page do
    {:ok, view, _} = live(conn(), "/")
    render_async(view, 3_000)
    view
  end

  defp triage(view, name) do
    view |> form("#triage-form", %{"name" => name}) |> render_submit()
    render_async(view, 3_000)
  end

  defp with_api(extra) do
    api = Application.fetch_env!(:sprite_triage, :api_options)
    Application.put_env(:sprite_triage, :api_options, Keyword.merge(api, extra))
    on_exit(fn -> Application.put_env(:sprite_triage, :api_options, api) end)
  end

  setup do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  defp list(names),
    do: {200, %{"sprites" => Enum.map(names, &%{"name" => &1, "status" => "cold"})}}

  test "without a token the page says so and calls nothing" do
    counter = Stubs.api(%{list: list(["box"])})
    with_api(token: nil)

    view = open_page()
    assert has_element?(view, "#no-token")
    refute render_async(view) =~ "Could not list Sprites"
    render_submit(view, "triage", %{"name" => "box"})
    assert Stubs.calls(counter, :list) == 0
    assert Stubs.calls(counter, :sprite) == 0
  end

  test "lists Sprites from the API without triaging any of them" do
    counter = Stubs.api(%{list: list(["box", "other"])})
    view = open_page()
    assert has_element?(view, "#sprite-other")
    assert render(view) =~ "not a health signal"
    assert Stubs.calls(counter, :check) == 0
  end

  test "wedged Sprite: plain headline, traffic stopped first, one restart with its sources, a note" do
    Stubs.api(%{
      list: list(["box"]),
      sprite: {200, Stubs.sprite("warm"), [{"fly-request-id", "01SPRITEREQ"}]},
      check: :hang
    })

    view = open_page()
    view |> element("#sprite-box button") |> render_click()
    html = render_async(view, 3_000)

    assert html =~ "The Sprites API answers, the Sprite itself does not"
    assert has_element?(view, "#next-step", "Stop clients")
    assert has_element?(view, "#do li", "Restart the Sprite once")
    assert has_element?(view, ~s(#do a[href="https://community.fly.io/t/28383"]))
    refute has_element?(view, "#do li", "Stop clients")
    assert html =~ "01SPRITEREQ"
    assert has_element?(view, "#note")
    refute html =~ "test-token"
  end

  test "by default a healthy /check is not the last word: a hanging command shows the wedge" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    with_api(spawn: &Stubs.spawn_hanging/2)
    view = open_page()
    assert triage(view, "box") =~ "The Sprites API answers, the Sprite itself does not"
  end

  # One row per state: what the API stubs answer, and words the result must contain.
  @states [
    {"ok", %{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}},
     "The Sprite itself takes commands"},
    {"ok after suspended", %{sprite: {200, Stubs.sprite()}, check: {200, Stubs.suspended()}},
     "it was waking up"},
    {"control_only", %{sprite: {200, Stubs.sprite()}, check: :hang}, "Restart the Sprite once"},
    {"storage_not_ready", %{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}},
     "only Fly fixed this"},
    {"start_failed",
     %{
       sprite: {200, Stubs.sprite()},
       check: {200, %{"status" => "needs_repair", "reason" => "failed to start machine"}}
     }, "restarts failed"},
    {"unknown_network", %{sprite: :timeout}, "status.flyio.net"},
    {"not_found", %{sprite: {404, %{"error" => "not found"}}}, "Sprite name"}
  ]

  test "every state shows its next step on the page, with a source" do
    for {state, stubs, words} <- @states do
      Stubs.api(stubs)
      view = open_page()
      html = triage(view, "box")
      assert has_element?(view, "#next-step .sources"), "#{state}: no next step with a source"
      assert html =~ words, "#{state}: missing #{words}"
    end
  end

  test "a Sprite that answers after saying it was suspended gets no note and no restart" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, Stubs.suspended()}})
    view = open_page()
    html = triage(view, "box")
    assert html =~ "The Sprite takes commands"
    assert has_element?(view, "#dont li", "machine in suspended state")
    refute has_element?(view, "#note")
  end

  test "a mistyped name gets no support note" do
    Stubs.api(%{sprite: {404, %{"error" => "not found"}}})
    view = open_page()
    html = triage(view, "nope")
    assert html =~ "No Sprite with this name"
    refute has_element?(view, "#note")
  end

  test "storage not ready: support, no restart suggested" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}})
    view = open_page()
    html = triage(view, "box")
    assert html =~ "storage is not ready"
    assert html =~ "only Fly fixed this"
    refute html =~ "Restart the Sprite once"
  end

  test "a second triage while one is running is ignored: one stuck Sprite, one /check" do
    counter = Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    view = open_page()
    view |> form("#triage-form", %{"name" => "box"}) |> render_submit()
    render_submit(view, "triage", %{"name" => "box"})
    render_async(view, 3_000)
    assert Stubs.calls(counter, :check) == 1
  end

  test "a stale note cannot be copied: the page re-checks its age on a timer" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    view = open_page()
    triage(view, "box")
    assert has_element?(view, "#copy-note")

    later = DateTime.add(DateTime.utc_now(), 301, :second)
    Application.put_env(:sprite_triage, :clock, fn -> later end)
    on_exit(fn -> Application.delete_env(:sprite_triage, :clock) end)
    # No manual :tick: the page's own timer (50 ms in tests) has to notice.
    Process.sleep(200)

    refute has_element?(view, "#copy-note")
    assert has_element?(view, "#stale")
  end
end
