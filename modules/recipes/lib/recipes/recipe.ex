defmodule Recipes.Recipe do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  schema "recipes_recipes" do
    field :name, :string
    field :directions, :string, default: ""

    has_many :recipe_ingredients, Recipes.RecipeIngredient,
      foreign_key: :recipe_id,
      on_replace: :delete,
      preload_order: [asc: :position]

    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:name, :directions])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> cast_assoc(:recipe_ingredients, with: &Recipes.RecipeIngredient.changeset/2)
  end
end
