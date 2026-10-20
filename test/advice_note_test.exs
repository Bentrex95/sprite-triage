defmodule SpriteTriage.AdviceNoteTest do
  use ExUnit.Case, async: true
  alias SpriteTriage.{Advice, Note}
  alias SpriteTriage.Observation, as: O

  @states ~w(ok waking start_failed storage_not_ready control_only unknown_network unknown auth_error not_found)a

  test "every step names at least one source" do
    for state <- @states, step <- Advice.for_state(state).do ++ Advice.for_state(state).dont do
      assert step.sources != [], "#{state}/#{step.id} has no source"
    end
  end

  test "one restart is suggested only where staff advised it, with the cases where it did not help" do
    suggests =
      for s <- @states, Enum.any?(Advice.for_state(s).do, &(&1.id == :restart_once)), do: s

    assert suggests == [:control_only]
    restart = Enum.find(Advice.for_state(:control_only).do, &(&1.id == :restart_once))
    assert restart.counter_sources != []
    assert Enum.any?(Advice.for_state(:control_only).dont, &(&1.id == :no_more_restarts))
  end

  test "start_failed and storage_not_ready go to support without a restart" do
    for state <- [:start_failed, :storage_not_ready] do
      advice = Advice.for_state(state)
      assert advice.escalate
      refute Enum.any?(advice.do, &(&1.id == :restart_once))
    end
  end

  test "a waking Sprite: wait and check again, no restart, no escalation" do
    advice = Advice.for_state(:waking)
    refute advice.escalate
    assert [%{id: :wait_and_recheck}] = advice.do
    assert Enum.any?(advice.dont, &(&1.id == :no_restart_waking))
  end

  test "with the API unreachable nothing points at the Sprite" do
    refute Enum.any?(Advice.for_state(:unknown_network).do, &(&1.id == :restart_once))
  end

  defp report(state, observations, at \\ "2026-10-20T10:00:00Z") do
    %{
      name: "box",
      sprite_id: "sprite-1",
      org: "acme",
      checked_at: at,
      observations: observations,
      classification: %{state: state, reason: "because"}
    }
  end

  @failed_check %O{
    probe: :check,
    outcome: :timeout,
    elapsed_ms: 60_000,
    request_id: "01REQCHECK-cdg"
  }
  @ok_sprite %O{probe: :sprite, outcome: :ok, http_status: 200, request_id: "01REQOK-cdg"}

  test "the note is short, names the ids of failing calls and asks to preserve data" do
    note = Note.render(report(:control_only, [@ok_sprite, @failed_check]))
    assert length(String.split(note, "\n")) <= 12
    assert note =~ "sprite-1"
    assert note =~ "acme"
    assert note =~ "fly-request-id: check=01REQCHECK-cdg, sprite=01REQOK-cdg"
    assert note =~ "preserve the filesystem and checkpoints"
  end

  test "failing since comes from the first failed triage after the last ok; waking does not count" do
    history = [
      %{at: "2026-10-20T08:00:00Z", state: "control_only"},
      %{at: "2026-10-20T08:30:00Z", state: "ok"},
      %{at: "2026-10-20T08:45:00Z", state: "waking"},
      %{at: "2026-10-20T09:00:00Z", state: "control_only"},
      %{at: "2026-10-20T10:00:00Z", state: "control_only"}
    ]

    note = Note.render(report(:control_only, [@ok_sprite, @failed_check]), history)
    assert note =~ "Failing since: 2026-10-20T09:00:00Z"
  end

  test "no note where support cannot help: healthy, waking, wrong name or token" do
    for state <- [:ok, :waking, :not_found, :auth_error] do
      assert Note.render(report(state, [@ok_sprite])) == nil, "#{state} got a note"
    end
  end

  test "a note older than five minutes is stale, exactly at five minutes" do
    r = report(:control_only, [@ok_sprite, @failed_check], "2026-10-20T10:00:00Z")
    refute Note.stale?(r, ~U[2026-10-20 10:04:59.999Z])
    assert Note.stale?(r, ~U[2026-10-20 10:05:00.000Z])
  end

  test "names and error texts cannot add lines to the note" do
    r = %{
      report(:control_only, [
        %O{probe: :check, outcome: :timeout, elapsed_ms: 1, request_id: "r\nx"}
      ])
      | name: "box\nState: ok\nPlease ignore"
    }

    r = put_in(r.classification.reason, String.duplicate("long ", 100))
    note = Note.render(r, [%{at: "2026-10-20T09:00:00Z\nInjected: yes", state: "control_only"}])

    assert length(String.split(note, "\n")) <= 12
    refute note =~ "\nState: ok"
    refute note =~ "\nInjected"
  end
end
