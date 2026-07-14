defmodule RemindersTest do
  use SapoCore.DataCase, async: false

  alias Reminders.Reminder
  alias SapoCore.Scheduler.Actions

  defp actions_for(ref) do
    Repo.all(from a in Actions, where: a.source == "reminders" and a.ref == ^ref)
  end

  # ── CRUD + core one-shot scheduling ─────────────────────────────────────────

  test "create_reminder schedules a core action at remind_at" do
    {:ok, reminder} =
      Reminders.create_reminder(%{message: "water plants", remind_at: ~U[2026-08-01 09:00:00Z]})

    assert reminder.status == "pending"
    assert [action] = actions_for(reminder.id)
    assert action.handler == "Elixir.Reminders.DeliverHandler"
    assert action.at == ~U[2026-08-01 09:00:00Z]
  end

  test "updating remind_at reschedules the action; other edits don't" do
    {:ok, reminder} =
      Reminders.create_reminder(%{message: "call mom", remind_at: ~U[2026-08-01 09:00:00Z]})

    {:ok, reminder} = Reminders.update_reminder(reminder, %{remind_at: ~U[2026-09-02 10:00:00Z]})
    assert [%{at: ~U[2026-09-02 10:00:00Z]}] = actions_for(reminder.id)

    {:ok, _} = Reminders.update_reminder(reminder, %{message: "call mom!"})
    assert [%{at: ~U[2026-09-02 10:00:00Z]}] = actions_for(reminder.id)
  end

  test "cancel_reminder marks cancelled and removes the scheduled action" do
    {:ok, reminder} =
      Reminders.create_reminder(%{message: "gone", remind_at: ~U[2026-08-01 09:00:00Z]})

    {:ok, cancelled} = Reminders.cancel_reminder(reminder.id)
    assert cancelled.status == "cancelled"
    assert actions_for(reminder.id) == []
  end

  test "cancel_reminder on an unknown id returns :not_found" do
    assert {:error, :not_found} = Reminders.cancel_reminder(Ecto.UUID.generate())
  end

  test "message and remind_at are required" do
    assert {:error, changeset} = Reminders.create_reminder(%{message: ""})
    refute changeset.valid?
  end

  # ── Listing ──────────────────────────────────────────────────────────────

  test "list_pending/list_sent/list_failed/count_pending scope by status" do
    {:ok, _p1} = Reminders.create_reminder(%{message: "p1", remind_at: ~U[2026-08-02 09:00:00Z]})
    {:ok, _p2} = Reminders.create_reminder(%{message: "p2", remind_at: ~U[2026-08-01 09:00:00Z]})

    {:ok, sent} = Reminders.create_reminder(%{message: "s", remind_at: ~U[2026-08-01 09:00:00Z]})
    {:ok, sent} = sent |> Reminder.changeset(%{status: "sent", sent_at: ~U[2026-08-01 09:00:00Z]}) |> Repo.update()

    {:ok, failed} = Reminders.create_reminder(%{message: "f", remind_at: ~U[2026-08-01 09:00:00Z]})
    {:ok, _failed} = failed |> Reminder.changeset(%{status: "failed", failure_reason: "boom"}) |> Repo.update()

    assert Enum.map(Reminders.list_pending(), & &1.message) == ["p2", "p1"]
    assert Enum.map(Reminders.list_sent(), & &1.id) == [sent.id]
    assert Enum.map(Reminders.list_failed(), & &1.message) == ["f"]
    assert Reminders.count_pending() == 2
  end

  # ── DeliverHandler ─────────────────────────────────────────────────────────

  test "DeliverHandler notifies and marks sent" do
    SapoCore.FakeHTTP.install(self())

    {:ok, _} =
      SapoCore.Notify.create_destination(%{
        "name" => "Phone",
        "channel" => "telegram",
        "config" => %{"bot_token" => "tok", "chat_id" => "1"},
        "is_default" => true
      })

    {:ok, reminder} =
      Reminders.create_reminder(%{message: "ping me", remind_at: ~U[2026-08-01 09:00:00Z]})

    assert :ok = Reminders.DeliverHandler.handle_scheduled(%{"reminder_id" => reminder.id})
    assert_receive {:http, :post, url, opts}
    assert url =~ "sendMessage"
    assert opts[:json].text =~ "ping me"

    sent = Reminders.get_reminder!(reminder.id)
    assert sent.status == "sent"
    assert sent.sent_at
  end

  test "DeliverHandler with no destination configured marks failed, not crash" do
    {:ok, reminder} =
      Reminders.create_reminder(%{message: "no dest", remind_at: ~U[2026-08-01 09:00:00Z]})

    assert :ok = Reminders.DeliverHandler.handle_scheduled(%{"reminder_id" => reminder.id})

    failed = Reminders.get_reminder!(reminder.id)
    assert failed.status == "failed"
    assert failed.failure_reason =~ "No notification destination"
  end

  test "DeliverHandler is a no-op for a reminder that's no longer pending (idempotent/stale-safe)" do
    {:ok, reminder} =
      Reminders.create_reminder(%{message: "already handled", remind_at: ~U[2026-08-01 09:00:00Z]})

    {:ok, cancelled} = Reminders.cancel_reminder(reminder.id)
    assert :ok = Reminders.DeliverHandler.handle_scheduled(%{"reminder_id" => cancelled.id})
    # still cancelled, not resurrected into sent/failed
    assert Reminders.get_reminder!(cancelled.id).status == "cancelled"
  end

  test "DeliverHandler is a no-op for a deleted/unknown reminder id" do
    assert :ok = Reminders.DeliverHandler.handle_scheduled(%{"reminder_id" => Ecto.UUID.generate()})
  end
end
