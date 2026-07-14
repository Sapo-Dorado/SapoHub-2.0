defmodule Reminders.Migrations.CreateReminders do
  use Ecto.Migration

  def change do
    create table(:reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message, :string, null: false
      add :remind_at, :utc_datetime, null: false
      add :time_specific, :boolean, null: false, default: true
      add :status, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime
      add :failure_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:reminders, [:status, :remind_at])
  end
end
