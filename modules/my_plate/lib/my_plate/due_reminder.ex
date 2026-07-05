defmodule MyPlate.DueReminder do
  @moduledoc """
  One-shot scheduled-action handler for task due-date reminders.

  Fired by the core scheduler at the task's remind time (possibly later,
  after downtime catch-up). Re-checks current task state so stale actions
  are harmless: completed/deleted tasks notify nothing.
  """

  @behaviour SapoKit.Scheduler.Handler

  alias MyPlate.Task
  alias SapoKit.Repo

  @impl true
  def handle_scheduled(%{"task_id" => task_id}) do
    case Repo.get(Task, task_id) do
      %Task{completed: false} = task ->
        case SapoKit.Notify.send("Task due: #{task.title}") do
          :ok -> :ok
          # No destination configured: drop rather than retry forever.
          {:error, :no_destination} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _completed_or_deleted ->
        :ok
    end
  end
end
