defmodule SapoCore.Repo.Migrations.CreateCoreScheduledActions do
  use Ecto.Migration

  def change do
    create table(:core_scheduled_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :at, :utc_datetime, null: false
      add :handler, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :source, :string, null: false
      add :ref, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:core_scheduled_actions, [:at])
    create index(:core_scheduled_actions, [:source, :ref])
  end
end
