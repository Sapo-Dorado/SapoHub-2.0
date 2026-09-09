defmodule ScheduledJobs.Run do
  @moduledoc """
  One execution of a `ScheduledJobs.Job` — either scheduler-triggered or
  a manual "run now". `output` is capped inline (see
  `ScheduledJobs.Module.config_schema/0`'s `inline_output_cap_bytes`);
  longer output spills to `output_path` under this module's storage dir.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  @triggers ~w(scheduled manual)
  @statuses ~w(running success failure)

  schema "scheduled_jobs_runs" do
    field :job_id, :binary_id
    field :trigger, :string
    field :status, :string, default: "running"
    field :exit_code, :integer
    field :output, :string
    field :output_path, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    timestamps()
  end

  def triggers, do: @triggers
  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:job_id, :trigger, :status, :started_at])
    |> validate_required([:job_id, :trigger, :started_at])
    |> validate_inclusion(:trigger, @triggers)
  end

  def finish_changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :exit_code, :output, :output_path, :finished_at])
    |> validate_required([:status, :finished_at])
    |> validate_inclusion(:status, @statuses)
  end
end
