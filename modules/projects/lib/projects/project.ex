defmodule Projects.Project do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  schema "projects_projects" do
    field :name, :string
    field :github_url, :string
    field :position, :integer, default: 0
    field :last_pulled_at, :utc_datetime

    has_many :params, Projects.ProjectParam, foreign_key: :project_id

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :github_url, :position, :last_pulled_at])
    |> validate_required([:name, :github_url])
    |> validate_format(:name, ~r/^[a-z0-9-]+$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:name)
  end
end
