defmodule SpriteTriage.TriageTest do
  # The whole triage against stubbed HTTP: real Req, real tasks, real deadlines (300 ms in tests).
  use ExUnit.Case, async: false
  alias SpriteTriage.Stubs

  setup do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  defp opts(extra \\ []), do: Application.fetch_env!(:sprite_triage, :api_options) ++ extra

  defp exec_ok(_name, _opts, _timeout),
    do: %SpriteTriage.Observation{probe: :exec, outcome: :ok, elapsed_ms: 5}

  test "wedged: the API answers, /check hangs and is killed at the deadline" do
    Stubs.api(%{
      sprite: {200, Stubs.sprite("warm"), [{"fly-request-id", "01SPRITE"}]},
      check: :hang
    })

    started = System.monotonic_time(:millisecond)
    r = SpriteTriage.triage("box", opts())
    elapsed = System.monotonic_time(:millisecond) - started

    assert r.classification.state == :control_only
    assert elapsed < 1_800, "the hung probe was not cut off (#{elapsed} ms)"
    assert Enum.find(r.observations, &(&1.probe == :check)).outcome == :timeout
    assert r.woke_sprite
  end

  test "probes run in parallel: two hung probes cost one deadline, not two" do
    Stubs.api(%{sprite: :hang, check: :hang})
    started = System.monotonic_time(:millisecond)
    r = SpriteTriage.triage("box", opts())
    elapsed = System.monotonic_time(:millisecond) - started

    # deadline 300 ms + 250 ms margin; waiting one after the other would take about 1100 ms
    assert elapsed < 950, "probes did not overlap (#{elapsed} ms)"
    assert r.classification.state == :unknown_network
  end

  test "a failing /check is asked once: no retries against a stuck Sprite" do
    counter = Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {503, "busy"}})
    # A deadline long enough that a retry (Req waits a second before the first one)
    # would happen and be counted.
    SpriteTriage.triage("box", Keyword.put(opts(), :deadlines, sprite: 300, check: 3_000))
    assert Stubs.calls(counter, :check) == 1
  end

  test "storage not ready from /check" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}})
    r = SpriteTriage.triage("box", opts())
    assert r.classification.state == :storage_not_ready
    assert r.note =~ "preserve the filesystem"
  end

  test "healthy Sprite, cold label: ok, and no note" do
    Stubs.api(%{sprite: {200, Stubs.sprite("cold")}, check: {200, %{"status" => "healthy"}}})
    r = SpriteTriage.triage("box", opts())
    assert r.classification.state == :ok
    assert r.note == nil
  end

  test "first wake after a quiet period: suspended, the command runs, ok and no note" do
    Stubs.api(%{sprite: {200, Stubs.sprite("cold")}, check: {200, Stubs.suspended()}})
    r = SpriteTriage.triage("box", opts(exec: &exec_ok/3))
    assert r.classification.state == :ok
    assert r.classification.reason =~ "waking up"
    assert r.note == nil
  end

  test "an API timeout is not blamed on the Sprite" do
    Stubs.api(%{sprite: :timeout, check: {200, %{"status" => "healthy"}}})
    assert SpriteTriage.triage("box", opts()).classification.state == :unknown_network
  end

  test "the command runs once, and only when the API and /check answered" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    exec = fn _name, _opts, _timeout ->
      Agent.update(calls, &(&1 + 1))
      %SpriteTriage.Observation{probe: :exec, outcome: :timeout, elapsed_ms: 300}
    end

    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "healthy"}}})
    r = SpriteTriage.triage("box", opts(exec: exec))
    assert Agent.get(calls, & &1) == 1
    assert r.classification.state == :control_only

    # A Sprite already known not to answer gets no command: a hung call keeps it busy.
    for stubs <- [
          %{sprite: :timeout, check: {200, %{"status" => "healthy"}}},
          %{sprite: {200, Stubs.sprite()}, check: :hang},
          %{sprite: {200, Stubs.sprite()}, check: {503, "Storage not ready"}},
          %{sprite: {200, Stubs.sprite()}, check: {200, %{"status" => "unknown-to-us"}}}
        ] do
      Stubs.api(stubs)
      SpriteTriage.triage("box", opts(exec: exec))
    end

    assert Agent.get(calls, & &1) == 1
  end

  test "the report and note never contain the token" do
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    r = SpriteTriage.triage("box", opts())
    refute inspect(r) =~ "test-token"
  end

  test "freshness counts from the start of the triage, not from the end of the probes" do
    {:ok, clock} = Agent.start_link(fn -> ~U[2026-10-20 10:00:00Z] end)

    Application.put_env(:sprite_triage, :clock, fn ->
      Agent.get_and_update(clock, fn t -> {t, DateTime.add(t, 100, :second)} end)
    end)

    on_exit(fn -> Application.delete_env(:sprite_triage, :clock) end)
    Stubs.api(%{sprite: {200, Stubs.sprite()}, check: :hang})
    assert SpriteTriage.triage("box", opts()).checked_at == "2026-10-20T10:00:00Z"
  end
end
