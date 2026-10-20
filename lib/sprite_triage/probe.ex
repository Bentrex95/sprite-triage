defmodule SpriteTriage.Probe do
  @moduledoc """
  Runs the probes with hard deadlines. Each probe is its own task; a probe that does not
  return in time is killed and recorded as `:timeout`, so one stuck call never blocks the
  others or the caller.

  First GET /v1/sprites/{name} and GET …/check, in parallel. When /check answers healthy,
  or says the machine is suspended (it is waking up), one exec of `true` follows. In the
  stuck reports the API and the VM looked fine while every command hung (sprites-docs#230);
  what /check said then is not reported, so the command is what decides. On real Sprites
  it also told a waking Sprite from a stuck one. It runs once and is never retried, and not
  at all when /check failed: the Sprite is then already known not to answer, and a hung
  call keeps a stuck Sprite busy (sprites-docs#231).
  """

  alias SpriteTriage.{Api, Classify, Exec, Observation}

  @deadlines %{sprite: 15_000, check: 60_000, exec: 45_000}

  def deadlines, do: @deadlines

  @spec run(String.t(), keyword()) :: [Observation.t()]
  def run(name, opts) do
    req = Api.new(opts)
    d = Map.merge(@deadlines, Map.new(Keyword.get(opts, :deadlines, [])))

    observations =
      parallel([
        {:sprite, fn -> Api.get_sprite(req, name, d.sprite) end, d.sprite},
        {:check, fn -> Api.check(req, name, d.check) end, d.check}
      ])

    sprite = Enum.find(observations, &(&1.probe == :sprite))
    check = Enum.find(observations, &(&1.probe == :check))

    if sprite.outcome == :ok and Classify.answered?(check) do
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
