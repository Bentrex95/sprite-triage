defmodule SpriteTriage.ClassifyTest do
  # Cases rebuilt from public forum threads (docs/cases.md). Each names the thread and
  # whether Fly staff confirmed the cause there. Our probes are not the user's
  # commands, so mapping their symptoms onto our probes is our assumption (`mapped: true`).
  use ExUnit.Case, async: true
  alias SpriteTriage.Classify
  alias SpriteTriage.Observation, as: O

  import SpriteTriage.Obs

  @iotimeout "failed to start sprite command: failed to connect: read tcp 10.0.0.1:55094->169.155.48.226:443: i/o timeout"

  @cases [
    # {thread, staff confirmed cause?, symptoms mapped onto our probes?, observations, expected}
    {"28383", true, true, [sprite("warm"), failed(:exec, :transport_error, @iotimeout)],
     :control_only},
    {"28561", false, true, [sprite("warm"), failed(:exec, :transport_error, @iotimeout)],
     :control_only},
    {"28659", true, true, [sprite("cold"), failed(:exec, :transport_error, @iotimeout)],
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
    {"28288", false, false, [sprite("cold"), check("healthy")], :ok}
  ]

  for {thread, confirmed, mapped, observations, expected} <- @cases do
    @tag thread: thread, staff_confirmed: confirmed, mapped: mapped
    test "forum #{thread}: #{expected}" do
      assert Classify.classify(unquote(Macro.escape(observations))).state == unquote(expected)
    end
  end

  test "the reported status is never used: unreachable and healthy Sprites show any of the three" do
    for status <- ~w(running warm cold) do
      assert Classify.classify([sprite(status), check("healthy")]).state == :ok

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

  test "an unexpected /check status is unknown, not ok" do
    result = Classify.classify([sprite(), check("degraded")])
    assert result.state == :unknown
    assert result.reason =~ "degraded", "the reason should name the status /check returned"
  end

  test "without /check there is not enough to say ok" do
    assert Classify.classify([sprite()]).state == :unknown
  end

  test "storage not ready wins over a generic failure" do
    obs = [
      sprite(),
      failed(:check, :timeout, "timeout"),
      failed(:exec, :transport_error, "Storage not ready")
    ]

    assert Classify.classify(obs).state == :storage_not_ready
  end

  describe "waking up (measured on real Sprites)" do
    # The first /check after 15 quiet minutes answered 200 with this body on every one of
    # seven Sprites; two minutes later it was healthy. A command inside ran fine.
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
    @exec_ok %O{probe: :exec, outcome: :ok}

    test "suspended while waking and no command run: waking, not a failure" do
      result = Classify.classify([sprite("cold"), @suspended])
      assert result.state == :waking
      assert result.reason =~ "suspended"
    end

    test "suspended while waking, but a command inside ran: ok" do
      assert Classify.classify([sprite("cold"), @suspended, @exec_ok]).state == :ok
    end

    test "suspended and the command inside failed: the Sprite does not answer" do
      obs = [sprite("cold"), @suspended, failed(:exec, :timeout, "timeout")]
      assert Classify.classify(obs).state == :control_only
    end

    test "needs_repair for any other reason stays unknown" do
      other = %{@suspended | body: %{"status" => "needs_repair", "reason" => "disk full"}}
      assert Classify.classify([sprite(), other, @exec_ok]).state == :unknown
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

    assert Classify.classify([sprite(), healthy]).state == :ok
  end
end
