defmodule SpriteTriage.ClassifyTest do
  # Cases rebuilt from public forum threads (docs/cases.md). Each names the thread and
  # whether Fly staff confirmed the cause there. Our probes are not the user's
  # commands, so mapping their symptoms onto our probes is our assumption (`mapped: true`).
  use ExUnit.Case, async: true
  alias SpriteTriage.Classify
  alias SpriteTriage.Observation, as: O

  import SpriteTriage.Obs

  @iotimeout "failed to start sprite command: failed to connect: read tcp 10.0.0.1:55094->169.155.48.226:443: i/o timeout"

  @exec_ok %O{probe: :exec, outcome: :ok}

  # The threads report what users saw from their own commands; that /check looked healthy
  # meanwhile is our assumption where it is not reported (`mapped: true`).
  @cases [
    # {thread, staff confirmed cause?, symptoms mapped onto our probes?, observations, expected}
    {"28383", true, true,
     [sprite("warm"), check("healthy"), failed(:exec, :transport_error, @iotimeout)],
     :control_only},
    {"28561", false, true,
     [sprite("warm"), check("healthy"), failed(:exec, :transport_error, @iotimeout)],
     :control_only},
    {"28659", true, true,
     [sprite("cold"), check("healthy"), failed(:exec, :transport_error, @iotimeout)],
     :control_only},
    {"28696", false, false,
     [
       sprite("cold"),
       check("unhealthy", "failed to start machine"),
       failed(:exec, :http_error, "", 502)
     ], :start_failed},
    {"28832", true, false, [sprite("cold"), check("unhealthy", "failed to start machine")],
     :start_failed},
    {"28785", true, true,
     [
       sprite("cold"),
       failed(:exec, :transport_error, "failed to start sprite command: Storage not ready")
     ], :storage_not_ready},
    {"28798", true, true,
     [
       sprite("cold"),
       failed(:exec, :transport_error, "failed to start sprite command: Storage not ready")
     ], :storage_not_ready},
    {"28835", true, true,
     [
       sprite("cold"),
       %O{probe: :check, outcome: :http_error, http_status: 503, body: "Storage not ready"}
     ], :storage_not_ready},
    {"28288", false, false, [sprite("cold"), check("healthy"), @exec_ok], :ok}
  ]

  for {thread, confirmed, mapped, observations, expected} <- @cases do
    @tag thread: thread, staff_confirmed: confirmed, mapped: mapped
    test "forum #{thread}: #{expected}" do
      assert Classify.classify(unquote(Macro.escape(observations))).state == unquote(expected)
    end
  end

  test "the reported status is never used: unreachable and healthy Sprites show any of the three" do
    for status <- ~w(running warm cold) do
      assert Classify.classify([sprite(status), check("healthy"), @exec_ok]).state == :ok

      assert Classify.classify([sprite(status), failed(:check, :timeout, "timeout")]).state ==
               :control_only
    end
  end

  test "control plane problems are not blamed on the Sprite" do
    assert Classify.classify([failed(:sprite, :timeout, "timeout")]).state == :unknown_network

    assert Classify.classify([failed(:sprite, :transport_error, "econnrefused")]).state ==
             :unknown_network

    assert Classify.classify([failed(:sprite, :http_error, "", 502)]).state == :unknown_network
  end

  test "token and name problems" do
    assert Classify.classify([failed(:sprite, :http_error, "", 401)]).state == :auth_error
    assert Classify.classify([failed(:sprite, :http_error, "", 404)]).state == :not_found
  end

  test "/check healthy but exec hangs: the machine is up but does not run commands" do
    assert Classify.classify([sprite(), check("healthy"), failed(:exec, :timeout, "timeout")]).state ==
             :control_only
  end

  test "a command that exits non-zero is named by its exit code, not as an HTTP error" do
    exited = %O{probe: :exec, outcome: :http_error, error: "exit 1"}
    result = Classify.classify([sprite(), check("healthy"), exited])
    assert result.state == :control_only
    assert result.reason =~ "exec ended with exit 1"
  end

  test "an unexpected /check status is unknown, not ok" do
    result = Classify.classify([sprite(), check("degraded"), @exec_ok])
    assert result.state == :unknown
    assert result.reason =~ "degraded", "the reason should name the status /check returned"
  end

  test "without /check, or without the command inside, there is not enough to say ok" do
    assert Classify.classify([sprite()]).state == :unknown
    assert Classify.classify([sprite(), check("healthy")]).state == :unknown
  end

  test "storage not ready wins over a generic failure" do
    obs = [
      sprite(),
      failed(:check, :timeout, "timeout"),
      failed(:exec, :transport_error, "Storage not ready")
    ]

    assert Classify.classify(obs).state == :storage_not_ready
  end

  describe "waking up (docs/measurements.md)" do
    # The first /check after a quiet period answered 200 with this body on all seven
    # Sprites measured, 18 times; the command inside ran, and later checks were healthy.
    @suspended %O{
      probe: :check,
      outcome: :ok,
      http_status: 200,
      body: %{
        "status" => "needs_repair",
        "reason" => "machine in suspended state",
        "elapsed" => 100
      }
    }

    test "suspended while waking, and the command inside ran: ok, with the reason" do
      result = Classify.classify([sprite("cold"), @suspended, @exec_ok])
      assert result.state == :ok
      assert result.reason =~ "waking up"
    end

    test "suspended and the command inside failed: the Sprite does not answer" do
      obs = [sprite("cold"), @suspended, failed(:exec, :timeout, "timeout")]
      assert Classify.classify(obs).state == :control_only
    end

    test "needs_repair for any other reason stays unknown" do
      other = %{@suspended | body: %{"status" => "needs_repair", "reason" => "disk full"}}
      assert Classify.classify([sprite(), other, @exec_ok]).state == :unknown
    end

    test "a command is worth one try after healthy or suspended, not after anything else" do
      assert Classify.answered?(check("healthy"))
      assert Classify.answered?(@suspended)
      refute Classify.answered?(check("degraded"))
      refute Classify.answered?(check("unhealthy", "failed to start machine"))
      refute Classify.answered?(failed(:check, :timeout, "timeout"))
      refute Classify.answered?(nil)
    end
  end

  test "HTTP errors from /check are about the token, the name or the API, never a restart case" do
    error = fn status ->
      %O{probe: :check, outcome: :http_error, http_status: status, body: ""}
    end

    assert Classify.classify([sprite(), error.(401)]).state == :auth_error
    assert Classify.classify([sprite(), error.(404)]).state == :not_found
    assert Classify.classify([sprite(), error.(429)]).state == :unknown
    assert Classify.classify([sprite(), error.(500)]).state == :unknown

    assert Classify.classify([sprite(), failed(:check, :timeout, "timeout")]).state ==
             :control_only
  end

  test "Storage not ready in the reason of an answered /check counts, elsewhere in the body not" do
    assert Classify.classify([sprite(), check("unhealthy", "Storage not ready")]).state ==
             :storage_not_ready

    healthy = check("healthy")

    healthy = %{
      healthy
      | body: Map.put(healthy.body, "last_error", "Storage not ready (yesterday)")
    }

    assert Classify.classify([sprite(), healthy, @exec_ok]).state == :ok
  end
end
