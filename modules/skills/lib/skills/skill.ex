defmodule Skills.Skill do
  @moduledoc """
  A tracked Claude Code skill — either a marketplace plugin
  (`kind: "marketplace"`, `name@marketplace` installed via `claude plugin`)
  or a custom skill (`kind: "custom"`, a folder under this module's storage
  `custom/` directory, live-installed into `~/.claude/skills` via a
  standing symlink — see `Skills.reconcile!/0`).
  """
  use SapoKit.Schema

  import Ecto.Changeset

  @kinds ~w(marketplace custom)

  schema "skills" do
    field :name, :string
    field :kind, :string
    field :marketplace, :string

    timestamps()
  end

  def kinds, do: @kinds

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:name, :kind, :marketplace])
    |> validate_required([:name, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:name)
  end
end
