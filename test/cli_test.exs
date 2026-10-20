defmodule SpriteTriage.CLITest do
  # The command line is the interface agents use: exit codes and JSON are its contract.
  use ExUnit.Case, async: false
  alias SpriteTriage.{CLI, Stubs}

  setup do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  defp api, do: Application.fetch_env!(:sprite_triage, :api_options)

  test "exit codes: 0 healthy, 1 not healthy, 2 token or name problem, 2 usage" do
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

  test "removed options are refused before any call: --restart, --no-check" do
    counter = Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})

    for argv <- [["box", "--restart", "--yes"], ["box", "--no-check", "--wake"]] do
      assert {2, out} = CLI.main(argv, api())
      assert out =~ "unknown options", "#{inspect(argv)} was accepted"
    end

    assert Stubs.calls(counter, :sprite) == 0
  end

  test "a waking Sprite exits 1 and says to run it again, without a support note" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, Stubs.suspended()}})
    {1, out} = CLI.main(["box"], api())
    assert out =~ "waking"
    assert out =~ "two minutes"
    refute out =~ "Note for Fly support"
  end

  test "a wrong name gets no support note" do
    Stubs.api(%{sprite: {404, %{"error" => "not found"}}})
    {2, out} = CLI.main(["nope"], api())
    refute out =~ "Note for Fly support"
  end

  test "a healthy Sprite gets no support note on the command line" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    {0, out} = CLI.main(["box"], api())
    refute out =~ "Note for Fly support"
  end

  test "--json prints machine-readable output" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    {0, out} = CLI.main(["box", "--json"], api())
    assert {:ok, %{"classification" => %{"state" => "ok"}}} = JSON.decode(out)
  end
end
