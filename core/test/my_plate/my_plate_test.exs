defmodule MyPlateTest do
  use SapoCore.DataCase, async: false

  alias MyPlate.RecurringTask
  alias MyPlate.Task
  alias SapoCore.Scheduler.Actions

  defp actions_for(ref) do
    Repo.all(from a in Actions, where: a.source == "my_plate" and a.ref == ^ref)
  end

  # ── Task CRUD + positions ──────────────────────────────────────────────────

  test "create_task appends at the end of its priority group" do
    {:ok, t1} = MyPlate.create_task(%{title: "a", priority: "high"})
    {:ok, t2} = MyPlate.create_task(%{title: "b", priority: "high"})
    {:ok, t3} = MyPlate.create_task(%{title: "c", priority: "low"})

    assert t1.position == 0
    assert t2.position == 1
    assert t3.position == 0
  end

  test "list_active_tasks orders by priority then position" do
    {:ok, _} = MyPlate.create_task(%{title: "low1", priority: "low"})
    {:ok, _} = MyPlate.create_task(%{title: "high1", priority: "high"})
    {:ok, _} = MyPlate.create_task(%{title: "med1", priority: "medium"})
    {:ok, _} = MyPlate.create_task(%{title: "high2", priority: "high"})

    assert Enum.map(MyPlate.list_active_tasks(), & &1.title) ==
             ["high1", "high2", "med1", "low1"]
  end

  test "reorder_task moves across priority groups and renumbers both" do
    {:ok, h1} = MyPlate.create_task(%{title: "h1", priority: "high"})
    {:ok, h2} = MyPlate.create_task(%{title: "h2", priority: "high"})
    {:ok, h3} = MyPlate.create_task(%{title: "h3", priority: "high"})
    {:ok, m1} = MyPlate.create_task(%{title: "m1", priority: "medium"})

    {:ok, _} = MyPlate.reorder_task(h2.id, "medium", 0)

    high = Enum.filter(MyPlate.list_active_tasks(), &(&1.priority == "high"))
    medium = Enum.filter(MyPlate.list_active_tasks(), &(&1.priority == "medium"))

    assert Enum.map(high, &{&1.title, &1.position}) == [{"h1", 0}, {"h3", 1}]
    assert Enum.map(medium, &{&1.title, &1.position}) == [{"h2", 0}, {"m1", 1}]
    assert Enum.map([h1, h3, m1], & &1.id) -- Enum.map(high ++ medium, & &1.id) == []
  end

  test "complete/uncomplete round trip" do
    {:ok, task} = MyPlate.create_task(%{title: "done me"})
    {:ok, completed} = MyPlate.complete_task(task.id)
    assert completed.completed
    assert completed.completed_at

    refute Enum.any?(MyPlate.list_active_tasks(), &(&1.id == task.id))

    {:ok, restored} = MyPlate.uncomplete_task(completed)
    refute restored.completed
    assert is_nil(restored.completed_at)
  end

  # ── Due-date reminders via core one-shot scheduling ────────────────────────

  test "task with due date schedules a core action; complete cancels it" do
    {:ok, task} = MyPlate.create_task(%{title: "due", due_date: ~D[2026-08-01]})

    assert [action] = actions_for(task.id)
    assert action.handler == "Elixir.MyPlate.DueReminder"
    assert action.at == ~U[2026-08-01 09:00:00Z]

    {:ok, _} = MyPlate.complete_task(task.id)
    assert actions_for(task.id) == []
  end

  test "changing the due date reschedules; removing it cancels" do
    {:ok, task} = MyPlate.create_task(%{title: "due", due_date: ~D[2026-08-01]})

    {:ok, task} = MyPlate.update_task(task, %{due_date: ~D[2026-09-02]})
    assert [%{at: ~U[2026-09-02 09:00:00Z]}] = actions_for(task.id)

    {:ok, _} = MyPlate.update_task(task, %{due_date: nil})
    assert actions_for(task.id) == []
  end

  test "DueReminder handler notifies only for live incomplete tasks" do
    SapoCore.FakeHTTP.install(self())

    {:ok, _} =
      SapoCore.Notify.create_destination(%{
        "name" => "Phone",
        "channel" => "telegram",
        "config" => %{"bot_token" => "tok", "chat_id" => "1"},
        "is_default" => true
      })

    {:ok, task} = MyPlate.create_task(%{title: "ping me", due_date: ~D[2026-08-01]})

    assert :ok = MyPlate.DueReminder.handle_scheduled(%{"task_id" => task.id})
    assert_receive {:http, :post, url, opts}
    assert url =~ "sendMessage"
    assert opts[:json].text =~ "ping me"

    # Completed task: no notification, still :ok (idempotent/stale-safe).
    {:ok, _} = MyPlate.complete_task(task.id)
    assert :ok = MyPlate.DueReminder.handle_scheduled(%{"task_id" => task.id})
    refute_receive {:http, _, _, _}

    # Deleted task: same.
    assert :ok = MyPlate.DueReminder.handle_scheduled(%{"task_id" => Ecto.UUID.generate()})
  end

  # ── Recurring: date math (v1 tests, verbatim expectations) ────────────────

  test "next_due_date daily/weekly/monthly" do
    daily = %RecurringTask{recurrence: "daily"}
    assert RecurringTask.next_due_date(daily, ~D[2026-07-04]) == ~D[2026-07-05]

    # 2026-07-04 is a Saturday (dow 6). Next Monday (1) = 07-06.
    weekly = %RecurringTask{recurrence: "weekly", day_of_week: 1}
    assert RecurringTask.next_due_date(weekly, ~D[2026-07-04]) == ~D[2026-07-06]

    # Same day-of-week: strictly after -> next week.
    weekly_sat = %RecurringTask{recurrence: "weekly", day_of_week: 6}
    assert RecurringTask.next_due_date(weekly_sat, ~D[2026-07-04]) == ~D[2026-07-11]

    monthly = %RecurringTask{recurrence: "monthly", day_of_month: 15}
    assert RecurringTask.next_due_date(monthly, ~D[2026-07-04]) == ~D[2026-07-15]
    assert RecurringTask.next_due_date(monthly, ~D[2026-07-20]) == ~D[2026-08-15]

    # Short months clamp.
    eom = %RecurringTask{recurrence: "monthly", day_of_month: 31}
    assert RecurringTask.next_due_date(eom, ~D[2026-02-01]) == ~D[2026-02-28]
  end

  test "weekly default create_ahead lands on Monday of the due week" do
    {:ok, rt} =
      MyPlate.create_recurring_task(%{
        title: "weekly",
        recurrence: "weekly",
        day_of_week: 5,
        active: false
      })

    assert rt.create_ahead_days == 4
  end

  # ── Recurring: instance creation + dedupe ──────────────────────────────────

  test "maybe_create_instance creates once and dedupes" do
    # Direct insert: create_recurring_task auto-creates the first instance
    # (v1 behavior), which would mask what this test isolates.
    {:ok, rt} =
      %RecurringTask{}
      |> RecurringTask.changeset(%{title: "daily chore", recurrence: "daily"})
      |> Repo.insert()

    today = ~D[2026-07-04]

    assert {:ok, task} = MyPlate.maybe_create_instance(rt, today)
    assert task.title == "daily chore"
    assert task.recurring_task_id == rt.id

    # Same day again: dedupe.
    rt = MyPlate.get_recurring_task!(rt.id)
    assert :skip = MyPlate.maybe_create_instance(rt, today)
  end

  test "create_ahead: instance not created before its window" do
    {:ok, rt} =
      %RecurringTask{}
      |> RecurringTask.changeset(%{
        title: "monthly report",
        recurrence: "monthly",
        day_of_month: 28,
        create_ahead_days: 3
      })
      |> Repo.insert()

    assert :skip = MyPlate.maybe_create_instance(rt, ~D[2026-07-10])
    assert {:ok, _} = MyPlate.maybe_create_instance(rt, ~D[2026-07-25])
  end

  test "RecurringHook catches up all owed instances in one run" do
    {:ok, rt} =
      MyPlate.create_recurring_task(%{
        title: "daily standup",
        recurrence: "daily",
        active: true,
        last_created_date: ~D[2026-07-01]
      })

    # Simulate one run happening 3 days late.
    assert :ok = MyPlate.RecurringHook.run(~U[2026-07-04 12:00:00Z])

    due_dates =
      Repo.all(
        from t in Task,
          where: t.recurring_task_id == ^rt.id,
          order_by: t.due_date,
          select: t.due_date
      )

    assert due_dates == [~D[2026-07-02], ~D[2026-07-03], ~D[2026-07-04]]

    # Running again is a no-op.
    assert :ok = MyPlate.RecurringHook.run(~U[2026-07-04 13:00:00Z])
    assert length(Repo.all(from t in Task, where: t.recurring_task_id == ^rt.id)) == 3
  end

  test "RecurringHook schedules hourly" do
    last = ~U[2026-07-04 10:17:42Z]

    assert MyPlate.RecurringHook.next_run_at(last, ~U[2026-07-04 10:30:00Z]) ==
             ~U[2026-07-04 11:00:00Z]

    assert MyPlate.RecurringHook.next_run_at(nil, ~U[2026-07-04 10:30:00Z]) ==
             ~U[2026-07-04 10:30:00Z]
  end
end
