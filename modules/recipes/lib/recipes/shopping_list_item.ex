defmodule Recipes.ShoppingListItem do
  @moduledoc """
  One line on the shopping list. At most one *open* (`checked: false`)
  item exists per ingredient — enforced by a partial unique index in the
  migration, not just app logic, so this invariant holds under
  concurrent requests too. `note` is the user's own freeform text
  (always optional); it's independent of the recipe-sourced amounts in
  `contributions`.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  schema "recipes_shopping_list_items" do
    field :note, :string
    field :checked, :boolean, default: false
    field :checked_at, :utc_datetime

    belongs_to :ingredient, Recipes.Ingredient
    has_many :contributions, Recipes.ShoppingListContribution, foreign_key: :shopping_list_item_id

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:note, :checked, :checked_at, :ingredient_id])
    |> validate_required([:ingredient_id])
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint(:ingredient_id, name: :recipes_shopping_list_items_open_ingredient_index)
  end
end
