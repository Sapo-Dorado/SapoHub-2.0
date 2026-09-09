defmodule ScheduledJobs.Migrations.CreateScheduledJobsTables do
  use Ecto.Migration

  def change do
    create table(:scheduled_jobs_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false
      add :command, :text, null: false
      add :cron, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :notify_mode, :string, null: false, default: "on_failure"
      add :notify_destination_id, :binary_id
      add :timeout_ms, :integer, null: false, default: 1_800_000
      add :last_checked_minute, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:scheduled_jobs_jobs, [:enabled])

    create table(:scheduled_jobs_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :job_id, references(:scheduled_jobs_jobs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :trigger, :string, null: false
      add :status, :string, null: false, default: "running"
      add :exit_code, :integer
      add :output, :text
      add :output_path, :string
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:scheduled_jobs_runs, [:job_id, :started_at])
  end
end
