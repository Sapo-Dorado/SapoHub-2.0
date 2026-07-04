defmodule SapoCore.Repo.Migrations.CreateCoreSchedulerRuns do
  use Ecto.Migration

  def change do
    create table(:core_scheduler_runs, primary_key: false) do
      add :hook_id, :string, primary_key: true
      add :last_run_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
