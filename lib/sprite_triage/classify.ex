defmodule SpriteTriage.Classify do
  @moduledoc """
  Turns probe observations into one state. Pure function, no I/O.

  The API `status` field (running/warm/cold) is never used: it was reported as warm,
  cold and running for Sprites that were unreachable, and as cold for one that was fine
  (forum threads 28561, 28659, 28696, sprites-docs#230, 28288; staff in 28774).

  States, checked in this order:

    * `:auth_error` / `:not_found` – the API answered 401/403 or 404
    * `:unknown_network`  – the API itself did not answer; from here we cannot tell our
                            own network from a Fly incident
    * `:storage_not_ready`– a probe returned "Storage not ready" (28785, 28798, 28835)
    * `:start_failed`     – /check says the machine failed to start (28696, 28832)
    * `:control_only`     – the API answers, the machine does not (/check or exec timed
                            out or failed): the "wedged" pattern (28383, 28561, 28659)
    * `:waking`           – /check says "machine in suspended state" and no command was
                            run. Measured on real Sprites: the first /check after a quiet
                            period answers this, and two minutes later it is healthy.
    * `:ok`               – /check healthy (or suspended while a command inside ran), and
                            the exec probe, if run, succeeded
    * `:unknown`          – anything else, including signals that contradict each other
  """

  alias SpriteTriage.Observation, as: Obs

  @type state ::
          :ok
          | :waking
          | :start_failed
          | :storage_not_ready
          | :control_only
          | :unknown_network
          | :unknown
          | :auth_error
          | :not_found

  @spec classify([Obs.t()]) :: %{state: state(), reason: String.t(), evidence: [atom()]}
  def classify(observations) do
    by = Map.new(observations, &{&1.probe, &1})
    sprite = by[:sprite]
    check = by[:check]
    exec = by[:exec]

    cond do
      is_nil(sprite) ->
        result(:unknown, "API probe missing", [])

      sprite.outcome == :http_error and sprite.http_status in [401, 403] ->
        result(:auth_error, "the API rejected the token (#{sprite.http_status})", [:sprite])

      sprite.outcome == :http_error and sprite.http_status == 404 ->
        result(:not_found, "no Sprite with this name in this organization", [:sprite])

      sprite.outcome != :ok ->
        result(:unknown_network, "the Sprites API did not answer normally: #{describe(sprite)}", [
          :sprite
        ])

      (hit = Enum.find(observations, &storage_not_ready?/1)) != nil ->
        result(:storage_not_ready, "#{hit.probe} returned \"Storage not ready\"", [hit.probe])

      start_failed?(check) ->
        result(:start_failed, "/check: #{check_reason(check)}", [:check])

      # Only a /check that did not answer at all points at the Sprite. HTTP errors from
      # it are about the token, the name, rate limits or the API itself.
      check != nil and check.outcome == :http_error and check.http_status in [401, 403] ->
        result(:auth_error, "/check rejected the token (#{check.http_status})", [:check])

      check != nil and check.outcome == :http_error and check.http_status == 404 ->
        result(:not_found, "/check did not find this Sprite", [:check])

      check != nil and check.outcome == :http_error ->
        result(:unknown, "/check returned HTTP #{check.http_status}", [:check])

      check != nil and check.outcome != :ok ->
        result(:control_only, "the Sprites API answers, /check #{describe(check)}", [
          :sprite,
          :check
        ])

      suspended?(check) and is_nil(exec) ->
        result(:waking, "/check: machine in suspended state (it is waking up)", [:check])

      check != nil and not healthy?(check) and not suspended?(check) ->
        result(:unknown, "/check returned status #{inspect(check_status(check))}", [:check])

      exec != nil and exec.outcome != :ok ->
        result(:control_only, "the Sprites API and /check answer, exec #{describe(exec)}", [
          :check,
          :exec
        ])

      suspended?(check) ->
        result(:ok, "/check said suspended while it woke up, and a command inside ran", [
          :check,
          :exec
        ])

      check != nil ->
        result(
          :ok,
          "/check healthy" <> if(exec, do: ", and a command inside ran", else: ""),
          [:check] ++ List.wrap(exec && :exec)
        )

      true ->
        result(:unknown, "not enough signals (run /check)", [:sprite])
    end
  end

  # On an answered call only the reason field counts, not unrelated metadata.
  defp storage_not_ready?(%Obs{outcome: :ok} = obs),
    do: check_reason(obs) =~ ~r/storage not ready/i

  defp storage_not_ready?(obs), do: Obs.text(obs) =~ ~r/storage not ready/i

  defp start_failed?(%Obs{outcome: :ok} = check),
    do: not healthy?(check) and check_reason(check) =~ ~r/failed to start/i

  defp start_failed?(_), do: false

  # Seen on every first /check after a quiet period: HTTP 200,
  # {"status": "needs_repair", "reason": "machine in suspended state"}.
  defp suspended?(%Obs{outcome: :ok} = check),
    do: check_status(check) == "needs_repair" and check_reason(check) =~ ~r/suspended state/i

  defp suspended?(_), do: false

  defp healthy?(check), do: check_status(check) == "healthy"
  defp check_status(%Obs{body: %{"status" => s}}), do: s
  defp check_status(_), do: nil
  defp check_reason(%Obs{body: %{"reason" => r}}) when is_binary(r), do: r
  defp check_reason(_), do: ""

  defp describe(%Obs{outcome: :timeout, elapsed_ms: ms}), do: "timed out after #{ms} ms"
  defp describe(%Obs{outcome: :http_error, http_status: s}), do: "returned HTTP #{s}"
  defp describe(%Obs{outcome: :transport_error, error: e}), do: "failed: #{e}"
  defp describe(%Obs{outcome: o}), do: to_string(o)

  defp result(state, reason, evidence), do: %{state: state, reason: reason, evidence: evidence}
end
