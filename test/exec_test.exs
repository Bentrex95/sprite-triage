defmodule SpriteTriage.ExecTest do
  # The exec probe's cleanup, with the SDK's spawn replaced by a function that behaves
  # like it: it may block before returning, and returns a command process that sends its
  # messages to the owner (the process that called spawn), as Sprites.Command does.
  # Cleanup is observed with monitors, not with sleeps.
  use ExUnit.Case, async: true
  alias SpriteTriage.Exec

  defp fake_command(owner, ref, exit_after) do
    spawn(fn ->
      if exit_after != :never do
        Process.sleep(exit_after)
        send(owner, {:exit, %{ref: ref}, 0})
      end

      Process.sleep(:infinity)
    end)
  end

  defp spawn_fun(test, opts) do
    fn _name, _opts ->
      if delay = opts[:connect_ms], do: Process.sleep(delay)
      ref = make_ref()
      pid = fake_command(self(), ref, Keyword.get(opts, :exit_after, :never))
      send(test, {:command, pid})
      {:ok, %{ref: ref, pid: pid}}
    end
  end

  defp assert_killed(cmd) do
    ref = Process.monitor(cmd)
    assert_receive {:DOWN, ^ref, :process, ^cmd, reason}, 1_000
    assert reason in [:killed, :noproc]
  end

  test "a command that never exits is killed at the deadline" do
    assert Exec.run_true("box", [spawn: spawn_fun(self(), [])], 200).outcome == :timeout
    assert_receive {:command, cmd}
    assert_killed(cmd)
  end

  test "a slow connect still ends with the command killed, after the caller gave up" do
    # The caller (here the test; in real use the probe task) stops waiting at 200 ms,
    # the SDK only hands over the command at 400 ms.
    opts = [spawn: spawn_fun(self(), connect_ms: 400)]
    assert Exec.run_true("box", opts, 200).outcome == :timeout
    assert_receive {:command, cmd}, 1_000
    assert_killed(cmd)
  end

  test "a command that exits on its own reports ok; its exit message reaches the guard" do
    opts = [spawn: spawn_fun(self(), exit_after: 20)]
    assert Exec.run_true("box", opts, 1_000).outcome == :ok
  end

  test "a crash while connecting is reported at once as a connection problem, not a hang" do
    spawn_fun = fn _name, _opts -> raise "connect blew up" end
    started = System.monotonic_time(:millisecond)
    obs = Exec.run_true("box", [spawn: spawn_fun], 1_000)
    assert obs.outcome == :transport_error
    assert obs.error =~ "connect blew up"
    assert System.monotonic_time(:millisecond) - started < 500
  end

  test "an SDK error is a transport error with its message" do
    spawn_fun = fn _name, _opts ->
      {:error, "failed to start sprite command: Storage not ready"}
    end

    obs = Exec.run_true("box", [spawn: spawn_fun], 500)
    assert obs.outcome == :transport_error
    assert obs.error =~ "Storage not ready"
  end
end
