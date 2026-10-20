defmodule SpriteTriage.Exec do
  @moduledoc """
  The one probe that runs inside the Sprite: `true`, through the official Elixir SDK.

  The SDK's command process is started unlinked and can block for a while while it
  connects, so whoever waits for it may give up (and be killed) first. The command is
  therefore owned by a separate guard process that is not linked to the probe: the
  guard waits for the SDK, and once it has the command it kills it as soon as the
  deadline has passed, even when the SDK hands it over late. What it cannot end is a
  connect that never returns: the SDK opens the connection inside its own unlinked
  process and sets no timeout for it.
  """

  alias SpriteTriage.Observation

  @doc """
  Options: `:token`, `:base_url`, and for tests `:spawn` – a function
  `(name, opts) -> {:ok, %{ref: ref, pid: pid}} | {:error, term}` replacing `Sprites.spawn/3`.
  """
  def run_true(name, opts, timeout) do
    caller = self()
    tag = make_ref()
    deadline = System.monotonic_time(:millisecond) + timeout
    at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    started = System.monotonic_time(:millisecond)

    spawn(fn -> send(caller, {tag, guard(name, opts, deadline)}) end)

    result =
      receive do
        {^tag, result} -> result
      after
        timeout -> {:error, :timeout}
      end

    observation(result, at, System.monotonic_time(:millisecond) - started)
  end

  defp guard(name, opts, deadline) do
    spawn_fun = Keyword.get(opts, :spawn, &sdk_spawn/2)

    case spawn_fun.(name, opts) do
      {:ok, cmd} -> collect(cmd, deadline - System.monotonic_time(:millisecond))
      {:error, reason} -> {:error, reason}
    end
  rescue
    # A crash while connecting is a connection problem, not a hang.
    e -> {:error, e}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp sdk_spawn(name, opts) do
    client = Sprites.new(Keyword.fetch!(opts, :token), Keyword.take(opts, [:base_url]))
    Sprites.spawn(Sprites.sprite(client, name), "true", [])
  end

  @doc false
  def collect(%{ref: ref, pid: pid}, remaining) do
    receive do
      {:exit, %{ref: ^ref}, code} -> {:ok, code}
      {:error, %{ref: ^ref}, reason} -> {:error, reason}
    after
      max(remaining, 0) ->
        Process.exit(pid, :kill)
        {:error, :timeout}
    end
  end

  defp observation(result, at, elapsed) do
    base = %Observation{
      probe: :exec,
      outcome: :ok,
      started_at: at,
      elapsed_ms: elapsed,
      wakes_sprite: true
    }

    case result do
      {:ok, 0} -> base
      {:ok, code} -> %{base | outcome: :http_error, error: "exit #{code}"}
      {:error, :timeout} -> %{base | outcome: :timeout, error: "timeout"}
      {:error, reason} -> %{base | outcome: :transport_error, error: message(reason)}
    end
  end

  defp message(%{__exception__: true} = e), do: Exception.message(e)
  defp message(reason) when is_binary(reason), do: reason
  defp message(reason), do: inspect(reason)
end
