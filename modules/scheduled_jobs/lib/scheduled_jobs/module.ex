defmodule ScheduledJobs.Module do
  @moduledoc """
  SapoKit.Module implementation for Scheduled Jobs: run a bash command
  or an assistant prompt on a cron schedule, with opt-in `SapoKit.Notify`
  alerts on completion.
  """
  use SapoKit.Module

  alias ScheduledJobsWeb.Api.JobsController
  alias ScheduledJobsWeb.Api.RunsController

  @impl true
  def id, do: :scheduled_jobs

  @impl true
  def title, do: "Scheduled Jobs"

  @impl true
  def icon, do: "hero-clock"

  @impl true
  def ui_routes do
    [
      %{path: "/scheduled-jobs", live_view: ScheduledJobsWeb.Live.Index, action: :index},
      %{path: "/scheduled-jobs/:id", live_view: ScheduledJobsWeb.Live.Show, action: :show}
    ]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/scheduled-jobs", controller: JobsController, action: :index},
      %{verb: :post, path: "/scheduled-jobs", controller: JobsController, action: :create},
      %{verb: :get, path: "/scheduled-jobs/:id", controller: JobsController, action: :show},
      %{verb: :patch, path: "/scheduled-jobs/:id", controller: JobsController, action: :update},
      %{verb: :delete, path: "/scheduled-jobs/:id", controller: JobsController, action: :delete},
      %{verb: :post, path: "/scheduled-jobs/:id/run", controller: JobsController, action: :run},
      %{verb: :get, path: "/scheduled-jobs/:id/runs", controller: RunsController, action: :index},
      %{verb: :get, path: "/scheduled-jobs/runs/:id", controller: RunsController, action: :show}
    ]
  end

  @impl true
  def scheduler_hooks, do: [ScheduledJobs.TickHook]

  @impl true
  def children(_config) do
    [{Task.Supervisor, name: ScheduledJobs.TaskSupervisor}]
  end

  @impl true
  def storage_paths, do: ["runs"]

  @impl true
  def ai_context do
    """
    Scheduled Jobs runs either a bash command or an assistant prompt
    (headless `claude -p`) on a cron schedule, with opt-in notification
    alerts on completion. #{ScheduledJobs.count_enabled()} job(s) enabled.
    Notify modes: always, on_failure (default), never. Use
    `sapo scheduled-jobs list|show|create|edit|delete|run` /
    `sapo scheduled-jobs-runs list|show` or the /api/scheduled-jobs
    endpoints. Schedules are stored as standard 5-field cron expressions
    (minute hour day-of-month month day-of-week).
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    If the user wants something to run automatically on a recurring
    schedule — a script on a timer, a periodic check-in prompt, a
    background sweep — offer to create a Scheduled Jobs entry
    (POST /api/scheduled-jobs) rather than tracking it yourself or
    proposing a one-off cron job outside the hub.
    """
  end

  @impl true
  def config_schema do
    [
      default_timeout_ms: [type: :pos_integer, default: 1_800_000],
      inline_output_cap_bytes: [type: :pos_integer, default: 65_536]
    ]
  end
end
