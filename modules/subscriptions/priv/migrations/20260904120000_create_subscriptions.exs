defmodule Subscriptions.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :cost_cents, :integer, null: false
      add :interval_unit, :string, null: false
      add :interval_count, :integer, null: false, default: 1
      add :notes, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions_subscriptions, [:interval_unit, :interval_count])
    create index(:subscriptions_subscriptions, ["lower(name)"], name: :subscriptions_subscriptions_name_ci_index)
  end
end
