defmodule SpriteTriage.Observation do
  @moduledoc """
  What one probe saw. Probes never interpret; `SpriteTriage.Classify` does.

    * `probe`      – `:sprite` (GET /v1/sprites/{name}), `:check` (GET …/check),
                     `:exec` (one `true` inside the Sprite), `:list` (the page's list)
    * `outcome`    – `:ok` (2xx), `:http_error`, `:timeout` (deadline hit, call killed),
                     `:transport_error` (no HTTP answer)
    * `request_id` – the `fly-request-id` response header, which Fly support asks for
  """

  @enforce_keys [:probe, :outcome]
  defstruct [
    :probe,
    :outcome,
    :http_status,
    :body,
    :error,
    :request_id,
    :started_at,
    :elapsed_ms,
    wakes_sprite: false
  ]

  @type t :: %__MODULE__{
          probe: :sprite | :check | :exec | :list,
          outcome: :ok | :http_error | :timeout | :transport_error,
          http_status: integer() | nil,
          body: map() | String.t() | nil,
          error: String.t() | nil,
          request_id: String.t() | nil,
          started_at: String.t() | nil,
          elapsed_ms: non_neg_integer() | nil,
          wakes_sprite: boolean()
        }

  @doc "All text a probe returned, for matching known error messages."
  def text(%__MODULE__{body: body, error: error}) do
    [error, if(is_binary(body), do: body, else: body && inspect(body))]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
