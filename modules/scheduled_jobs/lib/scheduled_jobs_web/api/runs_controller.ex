defmodule ScheduledJobsWeb.Api.RunsController do
  @moduledoc false
  use SapoKit.Web, :controller

  def index(conn, %{"id" => job_id}) do
    json(conn, Enum.map(ScheduledJobs.list_runs(job_id), &serialize/1))
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize(ScheduledJobs.get_run!(id)))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  defp serialize(run) do
    %{
      id: run.id,
      job_id: run.job_id,
      trigger: run.trigger,
      status: run.status,
      exit_code: run.exit_code,
      output: run.output,
      output_path: run.output_path,
      started_at: run.started_at,
      finished_at: run.finished_at
    }
  end
end
