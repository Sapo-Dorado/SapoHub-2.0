defmodule SapoCore.SchedulerTest do
  use SapoCore.DataCase, async: false

  import ExUnit.CaptureLog

  alias SapoCore.Scheduler
  alias SapoCore.Scheduler.Runs

  @test_pid_key {__MODULE__, :test_pid}

  # -- fake hooks (injected clock, report to the test process) ---------------

  defmodule HourlyHook do
    @behaviour SapoKit.Scheduler.Hook
    def hook_id, do: "test.hourly"
    def next_run_at(nil, now), do: now
    def next_run_at(last, _now), do: DateTime.add(last, 3600, :second)

    def run(now) do
      send(:persistent_term.get({SapoCore.SchedulerTest, :test_pid}), {:ran, :hourly, now})
      :ok
    end
  end

  defmodule BlockingHook do
    @behaviour SapoKit.Scheduler.Hook
    def hook_id, do: "test.blocking"
    def next_run_at(_last, now), do: now

    def run(_now) do
      test = :persistent_term.get({SapoCore.SchedulerTest, :test_pid})
      send(test, {:started, self()})

      receive do
        :continue -> :ok
      after
        5_000 -> :ok
      end
    end
  end

  defmodule FailingHook do
    @behaviour SapoKit.Scheduler.Hook
    def hook_id, do: "test.failing"
    def next_run_at(_last, now), do: now
    def run(_now), do: {:error, :boom}
  end

  defmodule RaisingHook do
    @behaviour SapoKit.Scheduler.Hook
    def hook_id, do: "test.raising"
    def next_run_at(_last, now), do: now
    def run(_now), do: raise("kaboom")
  end

  # -- helpers ----------------------------------------------------------------

  setup do
    :persistent_term.put(@test_pid_key, self())

    {:ok, clock} = Agent.start_link(fn -> ~U[2026-07-04 10:00:00Z] end)
    now_fun = fn -> Agent.get(clock, & &1) end
    set_now = fn dt -> Agent.update(clock, fn _ -> dt end) end

    %{now_fun: now_fun, set_now: set_now}
  end

  defp start_scheduler(hooks, now_fun) do
    start_supervised!({Scheduler, hooks: hooks, tick_ms: :manual, now_fun: now_fun, name: nil})
  end

  defp await_idle(pid) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    do_await_idle(pid, deadline)
  end

  defp do_await_idle(pid, deadline) do
    cond do
      Scheduler.running(pid) == [] ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("scheduler still running #{inspect(Scheduler.running(pid))}")

      true ->
        Process.sleep(10)
        do_await_idle(pid, deadline)
    end
  end

  # -- tests ------------------------------------------------------------------

  test "runs a due hook and persists last_run_at", %{now_fun: now_fun} do
    pid = start_scheduler([HourlyHook], now_fun)

    Scheduler.tick(pid)

    assert_receive {:ran, :hourly, ~U[2026-07-04 10:00:00Z]}, 1_000
    await_idle(pid)

    assert Runs.get_last_run("test.hourly") == ~U[2026-07-04 10:00:00Z]
  end

  test "does not run before next_run_at, runs once due (catch-up math)",
       %{now_fun: now_fun, set_now: set_now} do
    Runs.put_last_run("test.hourly", ~U[2026-07-04 10:00:00Z])
    pid = start_scheduler([HourlyHook], now_fun)

    # 30 minutes after last run: not due.
    set_now.(~U[2026-07-04 10:30:00Z])
    Scheduler.tick(pid)
    refute_receive {:ran, :hourly, _}, 200

    # 61 minutes after last run: due.
    set_now.(~U[2026-07-04 11:01:00Z])
    Scheduler.tick(pid)
    assert_receive {:ran, :hourly, ~U[2026-07-04 11:01:00Z]}, 1_000
    await_idle(pid)

    assert Runs.get_last_run("test.hourly") == ~U[2026-07-04 11:01:00Z]
  end

  test "a hook never overlaps itself", %{now_fun: now_fun} do
    pid = start_scheduler([BlockingHook], now_fun)

    Scheduler.tick(pid)
    assert_receive {:started, worker}, 1_000

    # Hook is always "due", but it's still running: no second start.
    Scheduler.tick(pid)
    Scheduler.tick(pid)
    refute_receive {:started, _}, 200
    assert Scheduler.running(pid) == ["test.blocking"]

    send(worker, :continue)
    await_idle(pid)

    # Once finished it can start again.
    Scheduler.tick(pid)
    assert_receive {:started, worker2}, 1_000
    send(worker2, :continue)
    await_idle(pid)
  end

  test "last_run_at survives a scheduler restart", %{now_fun: now_fun, set_now: set_now} do
    pid = start_scheduler([HourlyHook], now_fun)
    Scheduler.tick(pid)
    assert_receive {:ran, :hourly, _}, 1_000
    await_idle(pid)
    stop_supervised!(Scheduler)

    # Fresh scheduler, 5 minutes later: not due (last run persisted).
    set_now.(~U[2026-07-04 10:05:00Z])
    pid2 = start_scheduler([HourlyHook], now_fun)
    Scheduler.tick(pid2)
    refute_receive {:ran, :hourly, _}, 200
  end

  test "an {:error, _} result does not advance last_run_at", %{now_fun: now_fun} do
    pid = start_scheduler([FailingHook], now_fun)

    log =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log =~ "test.failing"
    assert Runs.get_last_run("test.failing") == nil
  end

  test "a crashing hook is retried and does not kill the scheduler", %{now_fun: now_fun} do
    pid = start_scheduler([RaisingHook], now_fun)

    log =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log =~ "test.raising"
    assert Runs.get_last_run("test.raising") == nil
    assert Process.alive?(pid)

    # Still due on the next tick (no last_run advanced).
    log2 =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log2 =~ "test.raising"
  end
end
