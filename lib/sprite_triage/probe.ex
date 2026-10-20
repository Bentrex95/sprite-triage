defmodule SpriteTriage.Probe do
  @moduledoc """
  Runs the probes with hard deadlines. Each probe is its own task; a probe that does not
  return in time is killed and recorded as `:timeout`, so one stuck call never blocks the
  others or the caller.

  Default probes touch only the control plane plus `/check`, which Fly offers for health:
  GET /v1/sprites/{name} and GET …/check. They run in parallel.

  `wake: true` adds one exec of `true` inside the Sprite, after the others and only if the
  control plane answered. It runs once and is never retried: in sprites-docs#231 a single
  hung call kept a stuck Sprite busy, and #230 reports zombie exec sessions.
  """

  alias SpriteTriage.{Api, Exec, Observation}

  @deadlines %{sprite: 15_000, check: 60_000, exec: 45_000}

  def deadlines, do: @deadlines

  @spec run(String.t(), keyword()) :: [Observation.t()]
  def run(name, opts) do
    req = Api.new(opts)
    d = Map.merge(@deadlines, Map.new(Keyword.get(opts, :deadlines, [])))

    probes =
      [{:sprite, fn -> Api.get_sprite(req, name, d.sprite) end, d.sprite}] ++
        if Keyword.get(opts, :check, true),
          do: [{:check, fn -> Api.check(req, name, d.check) end, d.check}],
          else: []

    observations = parallel(probes)
    sprite = Enum.find(observations, &(&1.probe == :sprite))

    if Keyword.get(opts, :wake, false) and sprite.outcome == :ok do
      exec = Keyword.get(opts, :exec, &Exec.run_true/3)
      observations ++ parallel([{:exec, fn -> exec.(name, opts, d.exec) end, d.exec}])
    else
      observations
    end
  end

  # Probes that may wake the Sprite; recorded even when the call is killed.
  @wakes [:check, :exec]

  # All deadlines count from one common start, so slow probes overlap instead of adding up.
  defp parallel(probes) do
    start = System.monotonic_time(:millisecond)

    probes
    |> Enum.map(fn {probe, fun, deadline} ->
      {probe, start, deadline, Task.Supervisor.async_nolink(SpriteTriage.TaskSupervisor, fun)}
    end)
    |> Enum.map(fn {probe, start, deadline, task} -> await(probe, start, deadline, task) end)
    |> Enum.map(&%{&1 | wakes_sprite: &1.wakes_sprite or &1.probe in @wakes})
  end

  # A small margin lets the HTTP client's own timeout fire first so we keep its error;
  # the kill is the backstop for calls that ignore it.
  defp await(probe, start, deadline, task) do
    remaining = max(start + deadline + 250 - System.monotonic_time(:millisecond), 0)

    case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
      {:ok, %Observation{} = obs} ->
        obs

      {:exit, reason} ->
        %Observation{
          probe: probe,
          outcome: :transport_error,
          error: "probe crashed: #{inspect(reason)}"
        }

      nil ->
        %Observation{
          probe: probe,
          outcome: :timeout,
          error: "killed after deadline",
          elapsed_ms: deadline
        }
    end
  end
end
