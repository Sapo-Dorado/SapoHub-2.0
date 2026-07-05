defmodule MyPlate do
  @moduledoc """
  Context for MyPlate task management (ported from v1).

  Due-date reminders go through CORE services — one-shot scheduling +
  Notify — instead of v1's direct Reminders coupling:
  `SapoKit.Scheduler.schedule_at(remind_at, MyPlate.DueReminder, ...)`.
  """

  import Ecto.Query

  alias MyPlate.RecurringTask
  alias MyPlate.Task
  alias SapoKit.Repo

  @doc "Today in the configured timezone (falls back to UTC)."
  def today(now \\ DateTime.utc_now()) do
    case DateTime.shift_zone(now, timezone()) do
      {:ok, local} -> DateTime.to_date(local)
      {:error, _} -> DateTime.to_date(now)
    end
  end

  defp timezone, do: SapoKit.ModuleConfig.get(:my_plate, :timezone) || "Etc/UTC"

  defp default_remind_time do
    case SapoKit.ModuleConfig.get(:my_plate, :default_remind_time) do
      time when is_binary(time) -> Time.from_iso8601!(time <> ":00")
      %Time{} = t -> t
      nil -> ~T[09:00:00]
    end
  end

  # ── Tasks ──────────────────────────────────────────────────────────────────

  def list_active_tasks do
    priority_order =
      dynamic(
        [t],
        fragment("CASE ? WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END", t.priority)
      )

    Task
    |> where([t], t.completed == false)
    |> order_by(^[asc: priority_order, asc: dynamic([t], t.position)])
    |> Repo.all()
  end

  def count_active_tasks do
    Repo.aggregate(where(Task, [t], t.completed == false), :count)
  end

  def count_due_today do
    today = today()

    Task
    |> where([t], t.completed == false and not is_nil(t.due_date) and t.due_date <= ^today)
    |> Repo.aggregate(:count)
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    priority = Map.get(attrs, "priority", "medium")
    attrs = Map.put(attrs, "position", next_position(priority))

    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn task ->
      if task.due_date, do: schedule_reminder(task)
      broadcast(:task_created, task)
    end)
  end

  def update_task(%Task{} = task, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    old_due_date = task.due_date

    task
    |> Task.changeset(attrs)
    |> Repo.update()
    |> tap_ok(fn updated ->
      handle_due_date_change(updated, old_due_date)
      broadcast(:task_updated, updated)
    end)
  end

  def complete_task(%Task{} = task) do
    task
    |> Task.changeset(%{completed: true, completed_at: DateTime.utc_now()})
    |> Repo.update()
    |> tap_ok(fn completed ->
      cancel_reminder(completed)
      broadcast(:task_updated, completed)
    end)
  end

  def complete_task(task_id) when is_binary(task_id), do: task_id |> get_task!() |> complete_task()

  def uncomplete_task(%Task{} = task) do
    task
    |> Task.changeset(%{completed: false, completed_at: nil})
    |> Repo.update()
    |> tap_ok(fn restored ->
      if restored.due_date, do: schedule_reminder(restored)
      broadcast(:task_updated, restored)
    end)
  end

  def delete_task(%Task{} = task) do
    cancel_reminder(task)

    task
    |> Repo.delete()
    |> tap_ok(&broadcast(:task_deleted, &1))
  end

  def delete_task(task_id) when is_binary(task_id), do: task_id |> get_task!() |> delete_task()

  def reorder_task(task_id, new_priority, new_position) do
    task = get_task!(task_id)

    Repo.transaction(fn ->
      {:ok, updated} =
        task
        |> Task.changeset(%{priority: new_priority, position: new_position})
        |> Repo.update()

      renumber_priority_group(new_priority, updated.id, new_position)

      if task.priority != new_priority do
        renumber_priority_group(task.priority, nil, nil)
      end

      broadcast(:task_updated, updated)
      updated
    end)
  end

  # ── Recurring tasks ────────────────────────────────────────────────────────

  def list_active_recurring_tasks do
    RecurringTask |> where([r], r.active == true) |> order_by([r], asc: r.title) |> Repo.all()
  end

  def list_all_recurring_tasks do
    RecurringTask |> order_by([r], asc: r.title) |> Repo.all()
  end

  def get_recurring_task!(id), do: Repo.get!(RecurringTask, id)

  def create_recurring_task(attrs) do
    %RecurringTask{}
    |> RecurringTask.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&maybe_create_instance(&1, today()))
  end

  def update_recurring_task(%RecurringTask{} = rt, attrs) do
    rt |> RecurringTask.changeset(attrs) |> Repo.update()
  end

  def delete_recurring_task(%RecurringTask{} = rt), do: Repo.delete(rt)

  def delete_recurring_task(id) when is_binary(id) do
    id |> get_recurring_task!() |> delete_recurring_task()
  end

  @doc """
  Creates a task instance for a recurring task if one is due.
  Returns `{:ok, task}`, `:skip`, or `{:error, reason}`. Idempotent per
  `{recurring_task_id, due_date}` — safe under scheduler catch-up/retries.
  """
  def maybe_create_instance(%RecurringTask{} = rt, today) do
    next_due = next_due_date_for(rt, today)
    create_on = Date.add(next_due, -rt.create_ahead_days)

    if Date.compare(today, create_on) != :lt do
      existing =
        Task
        |> where([t], t.recurring_task_id == ^rt.id and t.due_date == ^next_due)
        |> Repo.one()

      if existing do
        :skip
      else
        case create_task(%{
               title: rt.title,
               priority: rt.priority,
               due_date: next_due,
               recurring_task_id: rt.id
             }) do
          {:ok, task} ->
            rt |> RecurringTask.changeset(%{last_created_date: next_due}) |> Repo.update!()
            {:ok, task}

          error ->
            error
        end
      end
    else
      :skip
    end
  end

  defp next_due_date_for(%RecurringTask{last_created_date: nil} = rt, today) do
    RecurringTask.next_due_date(rt, Date.add(today, -1))
  end

  defp next_due_date_for(%RecurringTask{} = rt, _today) do
    RecurringTask.next_due_date(rt, rt.last_created_date)
  end

  # ── Due-date reminders (core scheduling + notify) ─────────────────────────

  defp schedule_reminder(%Task{} = task) do
    # Reschedule = cancel + schedule; the handler re-checks task state, so
    # stale actions are harmless either way.
    SapoKit.Scheduler.cancel_scheduled(:my_plate, task.id)

    SapoKit.Scheduler.schedule_at(
      remind_at(task.due_date),
      MyPlate.DueReminder,
      %{task_id: task.id},
      source: :my_plate,
      ref: task.id
    )
  end

  defp cancel_reminder(%Task{} = task) do
    SapoKit.Scheduler.cancel_scheduled(:my_plate, task.id)
  end

  defp handle_due_date_change(%Task{} = task, old_due_date) do
    cond do
      task.due_date == old_due_date -> :ok
      is_nil(task.due_date) -> cancel_reminder(task)
      true -> schedule_reminder(task)
    end
  end

  defp remind_at(%Date{} = due_date) do
    case DateTime.new(due_date, default_remind_time(), timezone()) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:error, _} -> DateTime.new!(due_date, default_remind_time(), "Etc/UTC")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp next_position(priority) do
    query =
      Task
      |> where([t], t.priority == ^priority and t.completed == false)
      |> select([t], max(t.position))

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  defp renumber_priority_group(priority, moved_task_id, new_position) do
    tasks =
      Task
      |> where([t], t.priority == ^priority and t.completed == false)
      |> order_by([t], asc: t.position)
      |> Repo.all()

    tasks =
      if moved_task_id do
        {moved, others} = Enum.split_with(tasks, &(&1.id == moved_task_id))

        case moved do
          [task] -> List.insert_at(others, min(new_position, length(others)), task)
          [] -> others
        end
      else
        tasks
      end

    tasks
    |> Enum.with_index()
    |> Enum.each(fn {task, idx} ->
      if task.position != idx do
        task |> Task.changeset(%{position: idx}) |> Repo.update!()
      end
    end)
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result

  defp broadcast(event, task) do
    SapoKit.PubSub.broadcast("my_plate:tasks", {event, task})
  end
end
