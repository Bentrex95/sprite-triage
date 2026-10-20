defmodule SpriteTriage.Note do
  @moduledoc """
  The support note: eight lines at most, with what Fly support asked for in the forum
  (Sprite name and id, organization, fly-request-id values, since when). Pure function.
  Only the person knows since when, so that line is left for them to fill in.
  Never contains a token. No name hashes: in thread 28659 hashing names made support look
  at the wrong Sprite. There is no note where support cannot help: a Sprite that
  answers, a wrong name or token, or an API that this machine cannot reach.

  Every value is cleaned of control characters and cut to `@max_field` characters, so
  one odd name or error text cannot add lines or bury the rest.

  A note is only meant to be sent while it is fresh: observations older than
  five minutes led to "it's alive and kicking" replies (28696).
  """

  @max_ids 5
  @max_field 120

  # Five minutes; configurable only so tests need not wait that long.
  def fresh_seconds, do: Application.get_env(:sprite_triage, :fresh_seconds, 300)

  @spec render(map()) :: String.t() | nil
  def render(%{classification: %{state: state}})
      when state in [:ok, :unknown_network, :not_found, :auth_error],
      do: nil

  def render(report) do
    %{state: state, reason: reason} = report.classification

    [
      "Sprite: #{clean(report.name)}" <>
        if(report[:sprite_id], do: " (#{clean(report.sprite_id)})", else: ""),
      report[:org] && "Organization: #{clean(report.org)}",
      "State: #{state} (#{clean(reason)})",
      "Failing since: (when did it start? add this before sending)",
      "Checked at: #{clean(report.checked_at, 40)}",
      ids(report) != [] && "fly-request-id: " <> Enum.join(ids(report), ", "),
      "Seen: " <> clean(Enum.map_join(report.observations, " · ", &summary/1), 400),
      "Please preserve the filesystem and checkpoints."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  @doc "Whether the note is five minutes old or older."
  @spec stale?(map(), DateTime.t()) :: boolean()
  def stale?(report, now) do
    {:ok, checked, _} = DateTime.from_iso8601(report.checked_at)
    DateTime.diff(now, checked, :millisecond) >= fresh_seconds() * 1000
  end

  @doc false
  def clean(value, max \\ @max_field)
  def clean(nil, _max), do: ""

  def clean(value, max) do
    value
    |> to_string()
    |> String.replace(~r/[\x00-\x1F\x7F]+/u, " ")
    |> String.slice(0, max)
  end

  # Ids of failing calls first; any id helps support find the logs (staff in 28774).
  defp ids(report) do
    report.observations
    |> Enum.filter(& &1.request_id)
    |> Enum.sort_by(&(&1.outcome == :ok))
    |> Enum.map(&"#{&1.probe}=#{clean(&1.request_id, 60)}")
    |> Enum.uniq()
    |> Enum.take(@max_ids)
  end

  defp summary(%{probe: p, outcome: :ok, http_status: s, body: %{"status" => st} = b})
       when is_binary(st),
       do: "#{p} #{s} #{st}" <> if(b["reason"], do: " (#{b["reason"]})", else: "")

  defp summary(%{probe: p, outcome: :ok, http_status: s}), do: "#{p} #{s || "ok"}"
  defp summary(%{probe: p, outcome: :http_error, http_status: s}), do: "#{p} HTTP #{s}"
  defp summary(%{probe: p, outcome: :timeout, elapsed_ms: ms}), do: "#{p} no answer in #{ms} ms"
  defp summary(%{probe: p, outcome: :transport_error}), do: "#{p} connection failed"
end
