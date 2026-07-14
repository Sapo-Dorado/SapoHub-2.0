defmodule Projects.Migrations.CreateProjectsTables do
  use Ecto.Migration

  def change do
    create table(:projects_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :github_url, :string, null: false
      add :position, :integer, null: false, default: 0
      add :last_pulled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects_projects, [:name])

    create table(:projects_project_params, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects_projects, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :value, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects_project_params, [:project_id, :key])
  end
end
