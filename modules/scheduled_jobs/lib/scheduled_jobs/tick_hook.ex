defmodule ScheduledJobs.TickHook do
  @moduledoc """
  Drives cron evaluation via the core scheduler, ticking every minute.
  `run/1` truncates `now` to the minute and checks every enabled job's
  cron expression against that ONE minute — deliberately NOT replaying
  every minute missed during downtime (unlike `MyPlate.RecurringHook`'s
  full backfill): a job fires once when its schedule matches the current
  tick, or not at all if the hub was asleep through the matching minute.
  That's standard cron behavior (a sleeping `cron(8)` doesn't replay
  missed slots either) and the right call here — task instances are
  cheap and safe to fully replay, job executions are not.

  `last_checked_minute` on each job is a dedupe guard, not a catch-up
  log: it only prevents the same minute from firing twice if `run/1` is
  retried.
  """

  @behaviour SapoKit.Scheduler.Hook

  require Logger

  alias ScheduledJobs.Cron
  alias ScheduledJobs.Job
  alias ScheduledJobs.Runner

  @impl true
  def hook_id, do: "scheduled_jobs.tick"

  @impl true
  def next_run_at(nil, now), do: now

  def next_run_at(last_run, _now) do
    %{last_run | second: 0, microsecond: {0, 0}}
    |> DateTime.add(60, :second)
  end

  @impl true
  def run(now) do
    minute = %{now | second: 0, microsecond: {0, 0}}

    for job <- ScheduledJobs.list_enabled_jobs() do
      maybe_fire(job, minute)
    end

    :ok
  end

  defp maybe_fire(%Job{last_checked_minute: minute} = _job, minute), do: :ok

  defp maybe_fire(%Job{} = job, minute) do
    with {:ok, cron} <- Cron.parse(job.cron),
         true <- Cron.matches?(cron, minute) do
      {:ok, job} = ScheduledJobs.mark_checked_minute(job, minute)
      Runner.run_async(job, "scheduled")
    else
      false ->
        ScheduledJobs.mark_checked_minute(job, minute)

      {:error, reason} ->
        Logger.error("ScheduledJobs.TickHook: job #{job.id} has an invalid cron: #{reason}")
    end

    :ok
  end
end
