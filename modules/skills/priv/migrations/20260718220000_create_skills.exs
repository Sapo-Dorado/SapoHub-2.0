defmodule Skills.Migrations.CreateSkills do
  use Ecto.Migration

  def change do
    create table(:skills, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      # "marketplace" | "custom"
      add :kind, :string, null: false
      # only set for kind == "marketplace"
      add :marketplace, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:skills, [:name])
  end
end
