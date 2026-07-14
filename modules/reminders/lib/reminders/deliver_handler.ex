defmodule Reminders.DeliverHandler do
  @moduledoc """
  One-shot scheduled-action handler that delivers a reminder.

  Fired by the core scheduler at `remind_at` (possibly later, after
  downtime catch-up — the scheduler guarantees at-least-once, so this must
  be idempotent). Re-checks the reminder's current status so a stale or
  already-handled action is harmless: only a still-`pending` reminder gets
  delivered.

  Replaces v1's bespoke `SapoHub.Reminders.Scheduler` GenServer
  (`Process.send_after` + hourly safety-net recheck) entirely — the core
  scheduler already provides persistence, restart catch-up, and retry.
  """

  @behaviour SapoKit.Scheduler.Handler

  alias Reminders.Reminder
  alias SapoKit.Repo

  @impl true
  def handle_scheduled(%{"reminder_id" => reminder_id}) do
    case Repo.get(Reminder, reminder_id) do
      %Reminder{status: "pending"} = reminder ->
        deliver(reminder)

      _already_handled_or_deleted ->
        :ok
    end
  end

  defp deliver(reminder) do
    case SapoKit.Notify.send("🔔 Reminder: #{reminder.message}") do
      :ok ->
        mark_sent(reminder)
        :ok

      {:error, :no_destination} ->
        # No destination configured: record it, don't retry forever.
        mark_failed(reminder, "No notification destination configured")
        :ok

      {:error, reason} ->
        # Any other failure: record it and stop too — v1 never retried a
        # failed delivery either, it just surfaced the reason for the user
        # to see and re-create the reminder if they want another attempt.
        mark_failed(reminder, "Delivery failed: #{inspect(reason)}")
        :ok
    end
  end

  defp mark_sent(reminder) do
    reminder
    |> Reminder.changeset(%{status: "sent", sent_at: DateTime.utc_now()})
    |> Repo.update()

    SapoKit.PubSub.broadcast("reminders:updates", :reminder_updated)
  end

  defp mark_failed(reminder, reason) do
    reminder
    |> Reminder.changeset(%{status: "failed", failure_reason: reason})
    |> Repo.update()

    SapoKit.PubSub.broadcast("reminders:updates", :reminder_updated)
  end
end
