defmodule SpriteTriage.Api do
  @moduledoc """
  The HTTP calls, each turned into an `SpriteTriage.Observation`.

  `/check` is not in the public OpenAPI (0.1.12) or the Elixir SDK; it comes from the
  official JS SDK (`checkSprite` in superfly/sprites-js) and from staff answers in the
  forum. Retries are off on purpose: a triage must not hammer a Sprite that is already
  stuck.
  """

  alias SpriteTriage.Observation

  @doc "Options: `:token` (required), `:base_url`, `:plug` (tests)."
  def new(opts) do
    Req.new(
      base_url: Keyword.get(opts, :base_url, "https://api.sprites.dev"),
      auth: {:bearer, Keyword.fetch!(opts, :token)},
      retry: false,
      redirect: false,
      # HTTP/1: when a probe is killed, its connection closes with it.
      connect_options: [protocols: [:http1]],
      plug: opts[:plug]
    )
  end

  def get_sprite(req, name, timeout),
    do: call(:sprite, req, :get, "/v1/sprites/#{encode(name)}", timeout)

  @doc "May wake the Sprite. Reports `failed to start machine` when a start fails."
  def check(req, name, timeout),
    do: %{
      call(:check, req, :get, "/v1/sprites/#{encode(name)}/check", timeout)
      | wakes_sprite: true
    }

  def list(req, timeout), do: call(:list, req, :get, "/v1/sprites", timeout)

  defp call(probe, req, method, url, timeout) do
    started = System.monotonic_time(:millisecond)
    at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    result = Req.request(req, method: method, url: url, receive_timeout: timeout)
    elapsed = System.monotonic_time(:millisecond) - started
    base = %Observation{probe: probe, outcome: :ok, started_at: at, elapsed_ms: elapsed}

    case result do
      {:ok, %Req.Response{status: status} = resp} ->
        %{
          base
          | outcome: if(status in 200..299, do: :ok, else: :http_error),
            http_status: status,
            body: trim(resp.body),
            request_id: header(resp, "fly-request-id")
        }

      {:error, %Req.TransportError{reason: :timeout}} ->
        %{base | outcome: :timeout, error: "timeout"}

      {:error, error} ->
        %{base | outcome: :transport_error, error: Exception.message(error)}
    end
  end

  defp header(resp, name), do: resp |> Req.Response.get_header(name) |> List.first()

  defp trim(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp trim(body), do: body

  defp encode(name), do: URI.encode(name, &URI.char_unreserved?/1)
end
