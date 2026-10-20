defmodule SpriteTriage.CLI do
  @moduledoc """
  The command line, as a function: arguments and API options in, `{exit_code, output}`
  out. `mix sprite_triage` only prints the output and exits with the code.

      mix sprite_triage NAME [--json]

    --json   print the full report as JSON (for scripts)

  Exit codes: 0 the Sprite answers, 1 it does not or the signals are unclear,
  2 usage, token or name problem.
  """

  @switches [json: :boolean]

  def usage, do: @moduledoc

  @spec main([String.t()], keyword()) :: {0 | 1 | 2, String.t()}
  def main(argv, api) do
    case parse(argv) do
      {:ok, opts, name} ->
        report = SpriteTriage.triage(name, api)

        {exit_code(report.classification.state), render(report, opts)}

      {:usage, message} ->
        {2, message <> "\n\n" <> @moduledoc}
    end
  end

  defp exit_code(:ok), do: 0
  defp exit_code(state) when state in [:auth_error, :not_found], do: 2
  defp exit_code(_), do: 1

  defp parse(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {_, _, [_ | _] = invalid} -> {:usage, "unknown options #{inspect(invalid)}"}
      {_, [], _} -> {:usage, "missing Sprite name"}
      {opts, [name | _], []} -> {:ok, opts, name}
    end
  end

  defp render(report, opts) do
    if opts[:json],
      do:
        JSON.encode!(
          Map.update!(report, :observations, &Enum.map(&1, fn o -> Map.from_struct(o) end))
        ),
      else: text(report)
  end

  defp text(report) do
    advice = report.advice

    [
      "#{report.name}: #{report.classification.state} – #{report.classification.reason}",
      report.woke_sprite && "(this triage may have woken the Sprite)",
      "",
      "Do:",
      Enum.map_join(advice.do, "\n", &"  - #{&1.text}"),
      advice.dont != [] && "Don't:",
      advice.dont != [] && Enum.map_join(advice.dont, "\n", &"  - #{&1.text}"),
      report.note && "",
      report.note && "Note for Fly support (re-check if older than 5 minutes):",
      report.note
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end
end
