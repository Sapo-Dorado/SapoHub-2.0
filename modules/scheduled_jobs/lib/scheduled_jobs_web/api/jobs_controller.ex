defmodule ScheduledJobsWeb.Api.JobsController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias ScheduledJobs.Job
  alias ScheduledJobs.Runner

  def index(conn, params) do
    json(conn, Enum.map(ScheduledJobs.list_jobs(params), &serialize/1))
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize(ScheduledJobs.get_job!(id)))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def create(conn, params) do
    case ScheduledJobs.create_job(params) do
      {:ok, job} -> conn |> put_status(:created) |> json(serialize(job))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case ScheduledJobs.update_job(id, Map.delete(params, "id")) do
      {:ok, job} -> json(conn, serialize(job))
      {:error, :not_found} -> render_not_found(conn)
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case ScheduledJobs.delete_job(id) do
      {:ok, _job} -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> render_not_found(conn)
    end
  end

  @doc "Manual 'run now' trigger, independent of the cron schedule."
  def run(conn, %{"id" => id}) do
    case ScheduledJobs.get_job(id) do
      nil ->
        render_not_found(conn)

      job ->
        {:ok, run} = Runner.run_async(job, "manual")
        conn |> put_status(:accepted) |> json(run_serialize(run))
    end
  end

  defp serialize(%Job{} = job) do
    %{
      id: job.id,
      name: job.name,
      kind: job.kind,
      command: job.command,
      cron: job.cron,
      enabled: job.enabled,
      notify_mode: job.notify_mode,
      notify_destination_id: job.notify_destination_id,
      timeout_ms: job.timeout_ms,
      last_checked_minute: job.last_checked_minute,
      inserted_at: job.inserted_at
    }
  end

  defp run_serialize(run) do
    %{
      id: run.id,
      job_id: run.job_id,
      trigger: run.trigger,
      status: run.status,
      started_at: run.started_at
    }
  end
end
