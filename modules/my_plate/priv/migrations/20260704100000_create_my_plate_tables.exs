defmodule MyPlate.Migrations.CreateMyPlateTables do
  use Ecto.Migration

  def change do
    create table(:my_plate_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :priority, :string, null: false, default: "medium"
      add :position, :integer
      add :due_date, :date
      add :completed, :boolean, null: false, default: false
      add :completed_at, :utc_datetime
      add :recurring_task_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:my_plate_tasks, [:completed, :priority, :position])
    create index(:my_plate_tasks, [:recurring_task_id, :due_date])

    create table(:my_plate_recurring_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :priority, :string, null: false, default: "medium"
      add :recurrence, :string, null: false
      add :day_of_week, :integer
      add :day_of_month, :integer
      add :create_ahead_days, :integer
      add :active, :boolean, null: false, default: true
      add :last_created_date, :date

      timestamps(type: :utc_datetime)
    end
  end
end
