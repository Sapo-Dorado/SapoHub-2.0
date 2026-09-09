defmodule ScheduledJobs do
  @moduledoc """
  Context for Scheduled Jobs: user-defined jobs (bash command or
  assistant prompt) that run on a cron schedule, with opt-in
  `SapoKit.Notify` alerts on completion.

  Execution lives in `ScheduledJobs.Runner`, the tick lives in
  `ScheduledJobs.TickHook`; this module is the CRUD + query surface used
  by both of those plus the API controllers, CLI, and LiveViews.
  """

  import Ecto.Query

  alias ScheduledJobs.Job
  alias ScheduledJobs.Run
  alias SapoKit.Repo

  @topic "scheduled_jobs:updates"

  def topic, do: @topic

  def run_topic(run_id), do: "scheduled_jobs:run:#{run_id}"

  # ── Jobs ─────────────────────────────────────────────────────────────────

  def list_jobs(filters \\ %{}) do
    Job
    |> maybe_filter_enabled(filters)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp maybe_filter_enabled(query, %{"enabled" => enabled}) when enabled in ["true", "false"] do
    where(query, enabled: ^(enabled == "true"))
  end

  defp maybe_filter_enabled(query, _filters), do: query

  def list_enabled_jobs do
    Job |> where(enabled: true) |> Repo.all()
  end

  def count_enabled do
    Job |> where(enabled: true) |> Repo.aggregate(:count)
  end

  def get_job!(id), do: Repo.get!(Job, id)
  def get_job(id), do: Repo.get(Job, id)

  def create_job(attrs) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast/1)
  end

  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
    |> tap_ok(&broadcast/1)
  end

  def update_job(id, attrs) when is_binary(id) do
    case get_job(id) do
      nil -> {:error, :not_found}
      job -> update_job(job, attrs)
    end
  end

  def delete_job(%Job{} = job) do
    Repo.delete(job)
    |> tap_ok(&broadcast/1)
  end

  def delete_job(id) when is_binary(id) do
    case get_job(id) do
      nil -> {:error, :not_found}
      job -> delete_job(job)
    end
  end

  @doc "Marks a job checked for the given (minute-truncated) tick, so the hook doesn't re-fire it within the same minute."
  def mark_checked_minute(%Job{} = job, %DateTime{} = minute) do
    job
    |> Job.checked_minute_changeset(minute)
    |> Repo.update()
  end

  # ── Runs ─────────────────────────────────────────────────────────────────

  def create_run(%Job{} = job, trigger) when trigger in ["scheduled", "manual"] do
    %{job_id: job.id, trigger: trigger, status: "running", started_at: DateTime.utc_now()}
    |> Run.create_changeset()
    |> Repo.insert()
    |> tap_ok(&broadcast/1)
  end

  def finish_run(%Run{} = run, attrs) do
    attrs = Map.put_new(attrs, :finished_at, DateTime.utc_now())

    run
    |> Run.finish_changeset(attrs)
    |> Repo.update()
    |> tap_ok(&broadcast/1)
  end

  def get_run!(id), do: Repo.get!(Run, id)

  def list_runs(job_id) do
    Run
    |> where(job_id: ^job_id)
    |> order_by(desc: :started_at)
    |> Repo.all()
  end

  @doc "Most recent run per job id, for list views. Only jobs with at least one run appear."
  def latest_runs_by_job(job_ids) do
    Run
    |> where([r], r.job_id in ^job_ids)
    |> order_by(desc: :started_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.job_id)
    |> Map.new(&{&1.job_id, &1})
  end

  @doc "True if any job's most recent run failed — used for the dashboard tile's attention state."
  def any_recent_failure? do
    ids = list_jobs() |> Enum.map(& &1.id)

    ids
    |> latest_runs_by_job()
    |> Map.values()
    |> Enum.any?(&(&1.status == "failure"))
  end

  defp broadcast(_record) do
    SapoKit.PubSub.broadcast(@topic, :updated)
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result
end
