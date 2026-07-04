defmodule SapoCore.Repo.Migrations.CreateCoreNotificationDestinations do
  use Ecto.Migration

  def change do
    create table(:core_notification_destinations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :channel, :string, null: false
      add :config, :map, null: false, default: %{}
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
