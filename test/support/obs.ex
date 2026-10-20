defmodule SpriteTriage.Obs do
  @moduledoc "Short constructors for observations in tests."
  alias SpriteTriage.Observation, as: O

  def sprite(status \\ "cold"),
    do: %O{probe: :sprite, outcome: :ok, http_status: 200, body: %{"status" => status}}

  def check(status, reason \\ nil),
    do: %O{
      probe: :check,
      outcome: :ok,
      http_status: 200,
      body: %{"status" => status, "reason" => reason}
    }

  def failed(probe, outcome, text, http \\ nil),
    do: %O{probe: probe, outcome: outcome, error: text, http_status: http}
end
