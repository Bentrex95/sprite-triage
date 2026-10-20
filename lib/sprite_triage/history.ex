defmodule SpriteTriage.History do
  @moduledoc """
  A local log of triages (one JSON object per line) under `:sprite_triage, :data_dir`,
  so the support note can say since when a Sprite has been failing. Fly support asks for
  that time, and people rarely have it.

  The log only adds context: a line that cannot be read is skipped, and a log that
  cannot be written does not stop a triage.
  """

  require Logger

  def path, do: Path.join(Application.fetch_env!(:sprite_triage, :data_dir), "history.jsonl")

  @doc "Appends one triage. Logs and carries on if the file cannot be written."
  def record(report) do
    line =
      JSON.encode!(%{
        sprite: report.name,
        id: report[:sprite_id],
        at: report.checked_at,
        state: to_string(report.classification.state)
      })

    with :ok <- File.mkdir_p(Path.dirname(path())),
         :ok <- File.write(path(), line <> "\n", [:append]) do
      :ok
    else
      {:error, reason} -> Logger.warning("history not written (#{reason}): #{path()}")
    end
  end

  @doc "Earlier triages of this Sprite, oldest first. Matched by id when known, else by name."
  def for_sprite(name, id) do
    case File.read(path()) do
      {:ok, data} ->
        data
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&decode/1)
        |> Enum.filter(&same_sprite?(&1, name, id))

      {:error, _} ->
        []
    end
  end

  @doc """
  When the current failure began: the first failing triage after the last `ok`. `waking`
  neither starts nor ends a failure. Pure function over `for_sprite/2`'s result.
  """
  @spec failing_since([map()]) :: String.t() | nil
  def failing_since(events) do
    events
    |> Enum.reject(&(&1.state == "waking"))
    |> Enum.reverse()
    |> Enum.take_while(&(&1.state != "ok"))
    |> List.last()
    |> case do
      nil -> nil
      event -> event.at
    end
  end

  defp decode(line) do
    case JSON.decode(line) do
      {:ok, %{"sprite" => s, "at" => at, "state" => st} = e}
      when is_binary(s) and is_binary(at) and is_binary(st) ->
        [%{sprite: s, id: e["id"], at: at, state: st}]

      _ ->
        []
    end
  end

  defp same_sprite?(%{id: eid}, _name, id) when is_binary(eid) and is_binary(id), do: eid == id
  defp same_sprite?(%{sprite: sprite}, name, _id), do: sprite == name
end
