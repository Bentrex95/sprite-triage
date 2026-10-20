defmodule SpriteTriage.CLITest do
  # Exit codes and JSON are the command line's contract for scripts.
  use ExUnit.Case, async: false
  alias SpriteTriage.{CLI, Stubs}

  setup do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  defp api, do: Application.fetch_env!(:sprite_triage, :api_options)

  test "exit codes: 0 the Sprite answers, 1 it does not, 2 token or name problem, 2 usage" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    assert {0, _} = CLI.main(["box"], api())

    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}})
    assert {1, out} = CLI.main(["box"], api())
    assert out =~ "storage_not_ready"

    Stubs.api(%{sprite: {401, %{"error" => "unauthorized"}}})
    assert {2, _} = CLI.main(["box"], api())

    assert {2, _} = CLI.main([], api())
    assert {2, _} = CLI.main(["box", "--bogus"], api())
  end

  test "a healthy /check with a hanging command exits 1" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    api = Keyword.put(api(), :spawn, &Stubs.spawn_hanging/2)
    assert {1, out} = CLI.main(["box"], api)
    assert out =~ "control_only"
  end

  test "a Sprite that answers after saying it was suspended exits 0, without a support note" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, Stubs.suspended()}})
    {0, out} = CLI.main(["box"], api())
    assert out =~ "waking up"
    refute out =~ "Note for Fly support"
  end

  test "a wrong name gets no support note" do
    Stubs.api(%{sprite: {404, %{"error" => "not found"}}})
    {2, out} = CLI.main(["nope"], api())
    refute out =~ "Note for Fly support"
  end

  test "--json prints machine-readable output" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    {0, out} = CLI.main(["box", "--json"], api())
    assert {:ok, %{"classification" => %{"state" => "ok"}}} = JSON.decode(out)
  end

  test "the demo API works from the command line too" do
    {code, out} = CLI.main(["demo-wedged"], SpriteTriage.Demo.api_options())
    assert code == 1
    assert out =~ "control_only"
  end
end
