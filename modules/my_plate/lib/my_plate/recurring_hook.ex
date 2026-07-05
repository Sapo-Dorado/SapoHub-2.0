defmodule MyPlate.RecurringHook do
  @moduledoc """
  Recurring-task instance creation via the core scheduler (replaces v1's
  dedicated GenServer). Runs at the top of every hour.

  Catch-up: `run/1` derives ALL owed instances from the recurring tasks'
  own state (`last_created_date` + date math), so a single delayed run
  after downtime creates everything that is due. `maybe_create_instance`
  dedupes per `{recurring_task_id, due_date}` — idempotent under retries.
  """

  @behaviour SapoKit.Scheduler.Hook

  @impl true
  def hook_id, do: "my_plate.recurring"

  @impl true
  def next_run_at(nil, now), do: now

  def next_run_at(last_run, _now) do
    # Top of the hour after the last successful run.
    %{last_run | minute: 0, second: 0, microsecond: {0, 0}}
    |> DateTime.add(3600, :second)
  end

  @impl true
  def run(now) do
    today = MyPlate.today(now)

    for rt <- MyPlate.list_active_recurring_tasks() do
      create_all_due(rt.id, today, 0)
    end

    :ok
  end

  # Create EVERY owed instance (not just the next one) — e.g. a daily task
  # after three days of downtime yields three instances in one run. The
  # bound is a safety net against pathological configs.
  defp create_all_due(_rt_id, _today, 100), do: :ok

  defp create_all_due(rt_id, today, count) do
    rt = MyPlate.get_recurring_task!(rt_id)

    case MyPlate.maybe_create_instance(rt, today) do
      {:ok, _task} -> create_all_due(rt_id, today, count + 1)
      _skip_or_error -> :ok
    end
  end
end
