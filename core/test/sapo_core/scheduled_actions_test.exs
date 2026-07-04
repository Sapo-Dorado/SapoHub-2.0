defmodule SapoCore.ScheduledActionsTest do
  use SapoCore.DataCase, async: false

  import ExUnit.CaptureLog

  alias SapoCore.Scheduler
  alias SapoCore.Scheduler.Actions

  @test_pid_key {__MODULE__, :test_pid}

  defmodule OkHandler do
    @behaviour SapoKit.Scheduler.Handler

    @impl true
    def handle_scheduled(payload) do
      send(:persistent_term.get({SapoCore.ScheduledActionsTest, :test_pid}), {:handled, payload})
      :ok
    end
  end

  defmodule FailHandler do
    @behaviour SapoKit.Scheduler.Handler

    @impl true
    def handle_scheduled(_payload), do: {:error, :nope}
  end

  setup do
    :persistent_term.put(@test_pid_key, self())

    {:ok, clock} = Agent.start_link(fn -> ~U[2026-07-04 12:00:00Z] end)
    now_fun = fn -> Agent.get(clock, & &1) end
    set_now = fn dt -> Agent.update(clock, fn _ -> dt end) end

    pid =
      start_supervised!(
        {Scheduler, hooks: [], actions: true, tick_ms: :manual, now_fun: now_fun, name: nil}
      )

    %{pid: pid, set_now: set_now}
  end

  defp await_idle(pid) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    do_await(pid, deadline)
  end

  defp do_await(pid, deadline) do
    cond do
      Scheduler.running(pid) == [] ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("scheduler busy")

      true ->
        Process.sleep(10)
        do_await(pid, deadline)
    end
  end

  defp count, do: Repo.aggregate(Actions, :count)

  test "fires a due action with string-keyed payload and deletes it", %{pid: pid} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 11:59:00Z], OkHandler, %{task_id: 7},
        source: :test,
        ref: "t7"
      )

    Scheduler.tick(pid)
    assert_receive {:handled, %{"task_id" => 7}}, 1_000
    await_idle(pid)
    assert count() == 0
  end

  test "does not fire future actions until due", %{pid: pid, set_now: set_now} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 13:00:00Z], OkHandler, %{}, source: :test, ref: "later")

    Scheduler.tick(pid)
    refute_receive {:handled, _}, 200
    assert count() == 1

    # Catch-up: jump past the scheduled time (as after downtime).
    set_now.(~U[2026-07-04 15:00:00Z])
    Scheduler.tick(pid)
    assert_receive {:handled, _}, 1_000
    await_idle(pid)
    assert count() == 0
  end

  test "failed actions are kept and retried", %{pid: pid} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 11:00:00Z], FailHandler, %{}, source: :test, ref: "f")

    log =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log =~ "kept for retry"
    assert count() == 1

    # Still fires on the next tick.
    log2 =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log2 =~ "kept for retry"
  end

  test "unresolvable handlers error and are kept", %{pid: pid} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 11:00:00Z], :"Elixir.Definitely.Not.A.Module", %{},
        source: :test,
        ref: "x"
      )

    log =
      capture_log(fn ->
        Scheduler.tick(pid)
        await_idle(pid)
      end)

    assert log =~ "cannot resolve handler"
    assert count() == 1
  end

  test "cancel_scheduled removes only the matching {source, ref}", %{pid: pid} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 13:00:00Z], OkHandler, %{}, source: :a, ref: "1")

    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 13:00:00Z], OkHandler, %{}, source: :a, ref: "2")

    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 13:00:00Z], OkHandler, %{}, source: :b, ref: "1")

    :ok = Scheduler.cancel_scheduled(:a, "1")
    assert count() == 2

    Scheduler.tick(pid)
    refute_receive {:handled, _}, 200
  end

  test "reschedule moves the action", %{pid: pid, set_now: set_now} do
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 13:00:00Z], OkHandler, %{}, source: :a, ref: "1")

    :ok = Scheduler.reschedule(:a, "1", ~U[2026-07-04 11:00:00Z])

    Scheduler.tick(pid)
    assert_receive {:handled, _}, 1_000
    await_idle(pid)
    assert count() == 0

    # And the other direction: push into the future.
    {:ok, _} =
      Scheduler.schedule_at(~U[2026-07-04 12:30:00Z], OkHandler, %{}, source: :a, ref: "2")

    :ok = Scheduler.reschedule(:a, "2", ~U[2026-07-04 18:00:00Z])
    set_now.(~U[2026-07-04 12:31:00Z])
    Scheduler.tick(pid)
    refute_receive {:handled, _}, 200
  end
end
