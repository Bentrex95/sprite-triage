defmodule SpriteTriageWeb.AccessKeyTest do
  # The page acts with the owner's token, so it is locked by a key printed at start.
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias SpriteTriage.Stubs
  alias SpriteTriageWeb.AccessKey

  @endpoint SpriteTriageWeb.Endpoint

  setup do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  defp list, do: {200, %{"sprites" => [%{"name" => "box", "status" => "cold"}]}}

  test "the page needs the key and does not leak it through the referrer" do
    Stubs.api(%{list: list()})
    assert build_conn() |> get("/") |> response(403) =~ "printed when it started"
    assert build_conn() |> get("/?key=wrong") |> response(403)

    conn = build_conn() |> get("/?key=test-key-0123456789")
    assert html_response(conn, 200) =~ "sprite-triage"
    assert Plug.Conn.get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert conn |> recycle() |> get("/") |> html_response(200) =~ "sprite-triage"
  end

  test "a LiveView socket without the access session gets nothing and can do nothing" do
    counter = Stubs.api(%{list: list(), sprite: {200, Stubs.sprite()}, check: :hang})
    {:ok, view, html} = live_isolated(build_conn(), SpriteTriageWeb.TriageLive, session: %{})
    assert html =~ "Open the address"
    render_click(view, "triage", %{"name" => "box"})
    assert Stubs.calls(counter, :list) == 0
    assert Stubs.calls(counter, :sprite) == 0
  end

  test "a replayed session cookie without the key gets a dead socket" do
    counter = Stubs.api(%{list: list(), sprite: {200, Stubs.sprite()}})
    conn = build_conn() |> Plug.Test.init_test_session(%{"access_ok" => true})
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Open the address"
    render_click(view, "triage", %{"name" => "box"})
    assert Stubs.calls(counter, :list) == 0
    assert Stubs.calls(counter, :sprite) == 0
  end

  describe "the configured key" do
    setup do
      configured = Application.fetch_env!(:sprite_triage, :access_key)
      on_exit(fn -> Application.put_env(:sprite_triage, :access_key, configured) end)
    end

    test "blank counts as unset and gets a random key" do
      Application.put_env(:sprite_triage, :access_key, "")
      AccessKey.setup!()
      assert byte_size(AccessKey.key()) >= 16
      refute AccessKey.valid?("")
    end

    test "must be at least 16 URL-safe characters, counted as characters" do
      for bad <- ["short", "ääääääää", "abc&def#ghi+jkl%mn"] do
        Application.put_env(:sprite_triage, :access_key, bad)
        assert_raise ArgumentError, fn -> AccessKey.setup!() end
      end

      Application.put_env(:sprite_triage, :access_key, "Good_key-0123456789")
      AccessKey.setup!()
      assert AccessKey.valid?("Good_key-0123456789")
    end
  end

  describe "a public demo" do
    setup do
      api = Application.fetch_env!(:sprite_triage, :api_options)

      on_exit(fn ->
        Application.put_env(:sprite_triage, :api_options, api)
        Application.delete_env(:sprite_triage, :public_demo)
      end)

      %{api: api}
    end

    test "needs no key, but only against the simulated API" do
      Application.put_env(:sprite_triage, :public_demo, true)
      Application.put_env(:sprite_triage, :api_options, SpriteTriage.Demo.api_options())
      AccessKey.setup!()
      assert AccessKey.valid?(nil)
      assert build_conn() |> get("/") |> html_response(200) =~ "Demo mode"
    end

    test "cannot be switched on with a real token" do
      Application.put_env(:sprite_triage, :public_demo, true)

      assert_raise ArgumentError, ~r/only works with mix sprite_triage.demo/, fn ->
        AccessKey.setup!()
      end

      refute AccessKey.valid?(nil)
      assert build_conn() |> get("/") |> response(403)
    end
  end
end
