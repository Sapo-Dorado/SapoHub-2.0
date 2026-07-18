defmodule Recipes.ShoppingListContribution do
  @moduledoc """
  A single recipe's attributed amount for a shopping-list item — never a
  manual add (those only ever touch `ShoppingListItem.note`). `recipe_name`
  is a snapshot taken when the contribution is created, so a shopping-list
  line still reads sensibly after the source recipe is renamed or deleted
  (`recipe_id` goes `nil` on delete; `recipe_name` doesn't change).
  """
  use SapoKit.Schema

  import Ecto.Changeset

  schema "recipes_shopping_list_contributions" do
    field :recipe_name, :string
    field :amount, :string

    belongs_to :shopping_list_item, Recipes.ShoppingListItem
    belongs_to :recipe, Recipes.Recipe

    timestamps(updated_at: false)
  end

  def changeset(contribution, attrs) do
    contribution
    |> cast(attrs, [:recipe_name, :amount, :shopping_list_item_id, :recipe_id])
    |> validate_required([:recipe_name, :amount, :shopping_list_item_id])
    |> foreign_key_constraint(:shopping_list_item_id)
    |> foreign_key_constraint(:recipe_id)
  end
end
