defmodule Recipes.RecipeIngredient do
  @moduledoc """
  One ingredient line on a recipe: which ingredient, how much (freeform
  text — no unit parsing, no structured quantity), and its position in
  the recipe's ingredient list.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  schema "recipes_recipe_ingredients" do
    field :amount, :string
    field :position, :integer, default: 0

    belongs_to :recipe, Recipes.Recipe
    belongs_to :ingredient, Recipes.Ingredient

    timestamps()
  end

  def changeset(recipe_ingredient, attrs) do
    recipe_ingredient
    |> cast(attrs, [:amount, :position, :ingredient_id])
    |> validate_required([:ingredient_id])
    |> foreign_key_constraint(:ingredient_id)
  end
end
