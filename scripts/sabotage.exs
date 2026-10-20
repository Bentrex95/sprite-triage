# Mutation check for the test suite. Each mutant breaks one rule on purpose; the named
# test must fail. A mutant that passes means no test guards that rule. A missing anchor
# or a compile error fails this script and never counts as "detected".
#
#   MIX_ENV=test mix run --no-start scripts/sabotage.exs

all_mutants = Code.eval_file(Path.join(__DIR__, "mutants.exs")) |> elem(0)

# SABOTAGE_ONLY=id1,id2 runs just those mutants (for checking a single new test quickly).
mutants =
  case System.get_env("SABOTAGE_ONLY") do
    nil -> all_mutants
    ids -> Enum.filter(all_mutants, &(elem(&1, 0) in String.split(ids, ",")))
  end

root = File.cwd!()

work =
  Path.join(System.tmp_dir!(), "sprite-triage-sabotage-#{System.unique_integer([:positive])}")

run_tests = fn dir ->
  System.cmd("mix", ["test", "--seed", "0"],
    cd: dir,
    env: [{"MIX_ENV", "test"}],
    stderr_to_stdout: true
  )
end

# The work tree is copied once (deps by symlink). Per mutant only the small source
# directories are copied again, so mix recompiles just what changed.
sources = ~w(mix.exs mix.lock config lib priv test)

refresh = fn ->
  for entry <- sources do
    target = Path.join(work, entry)
    File.rm_rf!(target)
    File.cp_r!(Path.join(root, entry), target)
  end
end

File.rm_rf!(work)
File.mkdir_p!(work)
File.ln_s!(Path.join(root, "deps"), Path.join(work, "deps"))
File.cp_r!(Path.join(root, "_build"), Path.join(work, "_build"))
refresh.()

{healthy_out, healthy_code} = run_tests.(work)
healthy = %{id: "healthy", passed: healthy_code == 0}
IO.puts("healthy baseline: #{if healthy.passed, do: "PASS", else: "FAIL"}")
if !healthy.passed, do: IO.puts(healthy_out)

results =
  for {id, file, from, to, expected} <- mutants do
    # Only the mutated file differs from the original; it is restored after each run,
    # so mix recompiles one file (and its dependents) instead of the whole project.
    path = Path.join(work, file)
    source = File.read!(Path.join(root, file))

    row =
      if String.contains?(source, from) do
        File.write!(path, String.replace(source, from, to, global: false))
        {out, code} = run_tests.(work)

        cond do
          out =~ "== Compilation error" or out =~ "CompileError" ->
            %{id: id, result: "compile_error"}

          code == 0 ->
            %{id: id, result: "SURVIVED"}

          String.contains?(out, expected) ->
            %{id: id, result: "detected"}

          true ->
            %{id: id, result: "failed_elsewhere", expected: expected}
        end
      else
        %{id: id, result: "anchor_missing"}
      end

    File.write!(path, source)

    IO.puts(String.pad_trailing(id, 30) <> row.result)
    row
  end

File.rm_rf!(work)
all_detected = healthy.passed and Enum.all?(results, &(&1.result == "detected"))
complete = length(mutants) == length(all_mutants)
# A run with SABOTAGE_ONLY is never reported as a full pass.
verdict =
  cond do
    all_detected and complete -> "PASS"
    all_detected -> "PARTIAL (#{length(mutants)} of #{length(all_mutants)} mutants run)"
    true -> "FAIL"
  end

File.write!(
  Path.join(root, "sabotage-result.json"),
  JSON.encode!(%{
    healthy: healthy,
    mutants: results,
    selected: length(mutants),
    total: length(all_mutants),
    complete: complete,
    verdict: verdict,
    passed: all_detected and complete
  })
)

detected = Enum.count(results, &(&1.result == "detected"))
IO.puts("\n#{detected}/#{length(results)} detected, healthy #{healthy.passed} -> #{verdict}")
System.halt(if all_detected, do: 0, else: 1)
