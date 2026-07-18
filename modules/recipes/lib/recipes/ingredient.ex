defmodule Recipes.Ingredient do
  @moduledoc """
  The canonical ingredient registry. Nothing about an ingredient is
  structured beyond its name — no unit, no category — recipes and
  shopping-list items each carry their own freeform amount text instead.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  schema "recipes_ingredients" do
    field :name, :string

    timestamps()
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> unique_constraint(:name, name: :recipes_ingredients_name_ci_index)
  end
end
