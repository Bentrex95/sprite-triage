defmodule SpriteTriage do
  @moduledoc """
  Triage for a Sprite that stopped answering: what the signals say, what is safe to do
  next, and a short note for Fly support. It reads; it never restarts or changes a Sprite
  (the optional exec probe runs `true` inside it).

      SpriteTriage.triage("my-sprite", token: token, wake: true)

  Options: `:token`, `:base_url`, `:check` (default true), `:wake` (default false),
  `:deadlines`, `:history` (default true), plus test hooks (`:plug`, `:spawn`, `:exec`).
  """

  alias SpriteTriage.{Advice, Classify, History, Note, Probe}

  @spec triage(String.t(), keyword()) :: map()
  def triage(name, opts) do
    # The note's age counts from the start: probes can take up to a minute.
    started = now()
    observations = Probe.run(name, opts)
    classification = Classify.classify(observations)
    sprite = Enum.find(observations, &(&1.probe == :sprite))
    body = if is_map(sprite.body), do: sprite.body, else: %{}

    report = %{
      name: name,
      sprite_id: string(body["id"]),
      org: string(body["organization"]),
      reported_status: body["status"],
      checked_at: started,
      observations: observations,
      woke_sprite: Enum.any?(observations, & &1.wakes_sprite),
      classification: classification,
      advice: Advice.for_state(classification.state)
    }

    # Read before writing, so "failing since" is about earlier runs.
    earlier =
      if history?(opts), do: History.for_sprite(name, report.sprite_id), else: []

    if history?(opts), do: History.record(report)

    Map.put(report, :note, Note.render(report, earlier ++ [history_event(report)]))
  end

  defp history_event(report),
    do: %{at: report.checked_at, state: to_string(report.classification.state)}

  defp history?(opts), do: Keyword.get(opts, :history, true)

  defp string(v) when is_binary(v), do: v
  defp string(_), do: nil

  defp now,
    do:
      Application.get_env(:sprite_triage, :clock, &DateTime.utc_now/0).()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()
end
