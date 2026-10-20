defmodule SpriteTriageWeb.LiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias SpriteTriage.Stubs

  @endpoint SpriteTriageWeb.Endpoint

  # A browser session that has passed the access key.
  defp conn,
    do:
      build_conn()
      |> Plug.Test.init_test_session(%{"access_ok" => true})
      |> put_connect_params(%{"key" => "test-key-0123456789"})

  # Opens the page and waits for the Sprite list started at mount, so no test races it.
  defp open_page do
    {:ok, view, _} = live(conn(), "/")
    render_async(view, 3_000)
    view
  end

  defp triage(view, name, wake \\ false) do
    params = if wake, do: %{"name" => name, "wake" => "true"}, else: %{"name" => name}
    view |> form("#triage-form", params) |> render_submit()
    render_async(view, 3_000)
  end

  defp with_api(extra) do
    api = Application.fetch_env!(:sprite_triage, :api_options)
    Application.put_env(:sprite_triage, :api_options, api ++ extra)
    on_exit(fn -> Application.put_env(:sprite_triage, :api_options, api) end)
  end

  defp hanging(_name, _opts),
    do: {:ok, %{ref: make_ref(), pid: spawn(fn -> Process.sleep(:infinity) end)}}

  setup do
    Req.Test.set_req_test_to_shared()
    File.rm_rf!(Application.fetch_env!(:sprite_triage, :data_dir))
    :ok
  end

  defp list(names),
    do: {200, %{"sprites" => Enum.map(names, &%{"name" => &1, "status" => "cold"})}}

  test "without a token the page says so and calls nothing" do
    counter = Stubs.api(%{list: list(["box"])})
    api = Application.fetch_env!(:sprite_triage, :api_options)
    Application.put_env(:sprite_triage, :api_options, Keyword.put(api, :token, nil))
    on_exit(fn -> Application.put_env(:sprite_triage, :api_options, api) end)

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

  test "wedged Sprite: plain headline, one restart suggested with its sources, request ids, a note" do
    Stubs.api(%{
      list: list(["box"]),
      sprite: {200, Stubs.sprite("warm"), [{"fly-request-id", "01SPRITEREQ"}]},
      check: :hang
    })

    view = open_page()
    view |> element("#sprite-box button") |> render_click()
    html = render_async(view, 3_000)

    assert html =~ "The Sprites API answers, the Sprite itself does not"
    assert has_element?(view, "#next-step", "Restart the Sprite once")
    assert has_element?(view, ~s(#do a[href="https://community.fly.io/t/28383"]))
    assert html =~ "01SPRITEREQ"
    assert has_element?(view, "#note")
    refute html =~ "test-token"
  end

  test "the page never restarts: there is no restart control at all" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    view = open_page()
    html = triage(view, "box")
    refute html =~ ~s(phx-click="restart")
    refute has_element?(view, "button", "Restart")
  end

  test "a waking Sprite: says so, says to check again, no note" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, Stubs.suspended()}})
    view = open_page()
    html = triage(view, "box")
    assert html =~ "The Sprite is waking up"
    assert has_element?(view, "#next-step", "two minutes")
    refute has_element?(view, "#note")
  end

  test "a mistyped name gets no support note" do
    Stubs.api(%{sprite: {404, %{"error" => "not found"}}})
    view = open_page()
    html = triage(view, "nope")
    assert html =~ "No Sprite with this name"
    refute has_element?(view, "#note")
  end

  test "storage not ready: support first, no restart suggested" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}})
    view = open_page()
    html = triage(view, "box")
    assert html =~ "storage is not ready"
    assert html =~ "only Fly fixed this"
    refute html =~ "Restart the Sprite once"
  end

  test "the exec probe is opt-in, and shows a Sprite whose /check is healthy but whose commands hang" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    with_api(spawn: &hanging/2)
    view = open_page()
    assert triage(view, "box") =~ "/check reports the Sprite as healthy"
    assert triage(view, "box", true) =~ "The Sprites API answers, the Sprite itself does not"
  end

  test "the list buttons use the checkbox on the form" do
    Stubs.api(%{
      list: list(["box"]),
      sprite: {200, Stubs.sprite()},
      check: {200, %{"status" => "healthy"}}
    })

    with_api(spawn: &hanging/2)
    view = open_page()
    view |> form("#triage-form", %{"name" => "", "wake" => "true"}) |> render_change()
    view |> element("#sprite-box button") |> render_click()
    assert render_async(view, 3_000) =~ "The Sprites API answers, the Sprite itself does not"
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

  test "the note expires at its deadline, not only at the next periodic tick" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    # checked_at is rounded down to the second, so one second of freshness can be gone
    # before the triage returns; two leave room.
    Application.put_env(:sprite_triage, :fresh_seconds, 2)
    Application.put_env(:sprite_triage, :tick_ms, 600_000)

    on_exit(fn ->
      Application.delete_env(:sprite_triage, :fresh_seconds)
      Application.put_env(:sprite_triage, :tick_ms, 50)
    end)

    view = open_page()
    triage(view, "box")
    assert has_element?(view, "#copy-note")
    Process.sleep(3_100)
    assert has_element?(view, "#stale")
  end
end
