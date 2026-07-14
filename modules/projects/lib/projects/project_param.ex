defmodule Projects.ProjectParam do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  schema "projects_project_params" do
    field :key, :string
    field :value, :string

    belongs_to :project, Projects.Project

    timestamps()
  end

  def changeset(param, attrs) do
    param
    |> cast(attrs, [:project_id, :key, :value])
    |> validate_required([:project_id, :key, :value])
    |> unique_constraint([:project_id, :key])
  end
end
