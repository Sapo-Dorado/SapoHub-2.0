defmodule Reminders do
  @moduledoc """
  Context for Reminders: manual, user-set reminders that deliver via
  `SapoKit.Notify` at a scheduled time (`SapoKit.Scheduler`, one-shot per
  reminder — see `Reminders.DeliverHandler`).

  Ported from v1's `SapoHub.Reminders`, minus:

    * calendar sync (`Calendar` is deferred hub-wide, not reminders-specific
      — see workspace/progress.md "Core services round 2")
    * `source_module`/`source_id` (other modules creating reminders on your
      behalf) — disallowed by the v2 module contract; see the moduledoc on
      `Reminders.Reminder`
    * the bespoke delivery `GenServer` — superseded by core's scheduler
  """

  import Ecto.Query

  alias Reminders.Reminder
  alias SapoKit.Repo

  @topic "reminders:updates"

  # ── CRUD ─────────────────────────────────────────────────────────────────

  def create_reminder(attrs) do
    %Reminder{}
    |> Reminder.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn reminder ->
      schedule_delivery(reminder)
      broadcast()
    end)
  end

  def update_reminder(reminder_id, attrs) when is_binary(reminder_id) do
    case Repo.get(Reminder, reminder_id) do
      nil -> {:error, :not_found}
      reminder -> update_reminder(reminder, attrs)
    end
  end

  def update_reminder(%Reminder{} = reminder, attrs) do
    old_remind_at = reminder.remind_at

    reminder
    |> Reminder.changeset(attrs)
    |> Repo.update()
    |> tap_ok(fn updated ->
      if updated.status == "pending" and DateTime.compare(updated.remind_at, old_remind_at) != :eq do
        schedule_delivery(updated)
      end

      broadcast()
    end)
  end

  def cancel_reminder(reminder_id) when is_binary(reminder_id) do
    case Repo.get(Reminder, reminder_id) do
      nil -> {:error, :not_found}
      reminder -> cancel_reminder(reminder)
    end
  end

  def cancel_reminder(%Reminder{} = reminder) do
    reminder
    |> Reminder.changeset(%{status: "cancelled"})
    |> Repo.update()
    |> tap_ok(fn cancelled ->
      SapoKit.Scheduler.cancel_scheduled(:reminders, cancelled.id)
      broadcast()
    end)
  end

  def get_reminder!(id), do: Repo.get!(Reminder, id)

  # ── Listing ──────────────────────────────────────────────────────────────

  def list_pending do
    Reminder
    |> where([r], r.status == "pending")
    |> order_by([r], asc: r.remind_at)
    |> Repo.all()
  end

  def list_sent do
    Reminder
    |> where([r], r.status == "sent")
    |> order_by([r], desc: r.sent_at)
    |> Repo.all()
  end

  def list_failed do
    Reminder
    |> where([r], r.status == "failed")
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
  end

  def count_pending do
    Repo.aggregate(where(Reminder, [r], r.status == "pending"), :count)
  end

  # ── Core one-shot scheduling ─────────────────────────────────────────────

  # Reschedule = cancel + schedule; DeliverHandler re-checks the reminder's
  # current status, so a stale action left behind by a race is harmless
  # either way (same pattern as `MyPlate.DueReminder`).
  defp schedule_delivery(%Reminder{} = reminder) do
    SapoKit.Scheduler.cancel_scheduled(:reminders, reminder.id)

    SapoKit.Scheduler.schedule_at(
      reminder.remind_at,
      Reminders.DeliverHandler,
      %{reminder_id: reminder.id},
      source: :reminders,
      ref: reminder.id
    )
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result

  defp broadcast, do: SapoKit.PubSub.broadcast(@topic, :reminder_updated)
end
