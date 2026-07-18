defmodule Recipes do
  @moduledoc """
  Context for Recipes: ingredient registry, recipes, and the shared
  shopping list.

  Two design points worth knowing before reading further:

  * **Contributions vs. notes.** A shopping-list item's recipe-sourced
    amounts live in `ShoppingListContribution` rows (one per recipe that
    contributed an amount) — that's the log the UI renders as "2 cups —
    Chicken Alfredo". A manual add (not from a recipe) never creates a
    contribution; it only ever touches the item's own freeform `note`
    field. The two are independent and both optional.
  * **At most one open item per ingredient.** Enforced by a partial
    unique index (`checked = 0`) in the migration, not just here — so
    `add_to_shopping_list/2` upserts (insert, retry-fetch on conflict)
    rather than "check then insert", and `uncheck_item/1` is merge-safe:
    unchecking an item can never collide with a newer open item for the
    same ingredient, it just combines the two.
  """

  import Ecto.Query

  alias Recipes.Ingredient
  alias Recipes.Recipe
  alias Recipes.RecipeIngredient
  alias Recipes.ShoppingListContribution
  alias Recipes.ShoppingListItem
  alias SapoKit.Repo

  # ── Ingredients ────────────────────────────────────────────────────────────

  def list_ingredients(query \\ nil) do
    Ingredient
    |> maybe_filter_name(query)
    |> order_by([i], asc: i.name)
    |> Repo.all()
  end

  def get_ingredient!(id), do: Repo.get!(Ingredient, id)

  def create_ingredient(attrs) do
    %Ingredient{} |> Ingredient.changeset(attrs) |> Repo.insert()
  end

  def update_ingredient(%Ingredient{} = ingredient, attrs) do
    ingredient |> Ingredient.changeset(attrs) |> Repo.update()
  end

  @doc """
  Deletes an ingredient, refusing (`{:error, :in_use}`) if any recipe or
  shopping-list item still references it — no silent cascades. Callers
  should surface the counts from `ingredient_usage/1` so the user knows
  what to clear first.
  """
  def delete_ingredient(%Ingredient{} = ingredient) do
    %{recipes: recipes, shopping_list: shopping_list} = ingredient_usage(ingredient.id)

    if recipes > 0 or shopping_list > 0 do
      {:error, :in_use}
    else
      Repo.delete(ingredient)
    end
  end

  def delete_ingredient(id) when is_binary(id), do: id |> get_ingredient!() |> delete_ingredient()

  @doc "How many recipes and shopping-list items reference this ingredient."
  def ingredient_usage(ingredient_id) do
    recipe_count =
      RecipeIngredient |> where([ri], ri.ingredient_id == ^ingredient_id) |> Repo.aggregate(:count)

    shopping_list_count =
      ShoppingListItem |> where([s], s.ingredient_id == ^ingredient_id) |> Repo.aggregate(:count)

    %{recipes: recipe_count, shopping_list: shopping_list_count}
  end

  defp maybe_filter_name(query_ast, nil), do: query_ast
  defp maybe_filter_name(query_ast, ""), do: query_ast

  defp maybe_filter_name(query_ast, text) do
    # SQLite's LIKE is case-insensitive for ASCII by default — no need for
    # a separate lower()/ilike dance here (unlike the uniqueness index,
    # which does need lower() to actually prevent "Eggs" vs "eggs").
    where(query_ast, [q], like(q.name, ^"%#{text}%"))
  end

  # ── Recipes ──────────────────────────────────────────────────────────────

  def list_recipes(query \\ nil) do
    Recipe
    |> maybe_filter_name(query)
    |> order_by([r], asc: r.name)
    |> Repo.all()
    |> Repo.preload(:recipe_ingredients)
  end

  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload(recipe_ingredients: [:ingredient])
  end

  def create_recipe(attrs) do
    %Recipe{} |> Recipe.changeset(normalize_recipe_attrs(attrs)) |> Repo.insert()
  end

  @doc "Updates a recipe. The ingredient list, if present in attrs, fully replaces the existing one."
  def update_recipe(%Recipe{} = recipe, attrs) do
    recipe
    |> Repo.preload(:recipe_ingredients)
    |> Recipe.changeset(normalize_recipe_attrs(attrs))
    |> Repo.update()
  end

  def delete_recipe(%Recipe{} = recipe), do: Repo.delete(recipe)
  def delete_recipe(id) when is_binary(id), do: id |> get_recipe!() |> delete_recipe()

  # Accepts either "ingredients" (the documented API shape) or
  # "recipe_ingredients" (matches the schema's assoc name directly), and
  # stamps `position` from list order — the client sends ingredients in
  # display order, not explicit positions.
  defp normalize_recipe_attrs(attrs) do
    attrs = stringify_keys(attrs)

    case Map.get(attrs, "ingredients") || Map.get(attrs, "recipe_ingredients") do
      nil ->
        attrs

      list ->
        indexed =
          list
          |> Enum.with_index()
          |> Enum.map(fn {entry, idx} -> entry |> stringify_keys() |> Map.put("position", idx) end)

        attrs |> Map.delete("ingredients") |> Map.put("recipe_ingredients", indexed)
    end
  end

  # ── Shopping list ──────────────────────────────────────────────────────────

  def list_shopping_list_items do
    open =
      ShoppingListItem
      |> where([s], s.checked == false)
      |> order_by([s], asc: s.inserted_at)
      |> preload([:ingredient, contributions: ^from(c in ShoppingListContribution, order_by: c.inserted_at)])
      |> Repo.all()

    checked =
      ShoppingListItem
      |> where([s], s.checked == true)
      |> order_by([s], desc: s.checked_at)
      |> preload([:ingredient, :contributions])
      |> Repo.all()

    %{open: open, checked: checked}
  end

  def get_shopping_list_item!(id) do
    ShoppingListItem
    |> Repo.get!(id)
    |> Repo.preload([:ingredient, contributions: from(c in ShoppingListContribution, order_by: c.inserted_at)])
  end

  def count_open_shopping_list_items do
    ShoppingListItem |> where([s], s.checked == false) |> Repo.aggregate(:count)
  end

  @doc """
  Adds an ingredient to the shopping list — the one entry point for both
  "swipe an ingredient in a recipe" and "type an item directly".

  * `recipe_id` + `amount` (both given): appends a
    `ShoppingListContribution` snapshotting the recipe's name and that
    amount. Safe to call repeatedly for the same ingredient from
    different recipes — each call just adds another contribution line.
  * `note`: sets the item's own freeform note (overwrites, doesn't
    append — it's a single user-editable field, not a log).

  Either, both, or neither may be given; a bare `add_to_shopping_list(id)`
  with no recipe/note just opens (or reuses) the item.
  """
  def add_to_shopping_list(ingredient_id, opts \\ %{}) do
    opts = stringify_keys(opts)

    Repo.transaction(fn ->
      item = get_or_create_open_item!(ingredient_id)

      item =
        case opts["note"] do
          nil -> item
          "" -> item
          note -> item |> ShoppingListItem.changeset(%{note: note}) |> Repo.update!()
        end

      case {opts["recipe_id"], opts["amount"]} do
        {recipe_id, amount} when is_binary(recipe_id) and is_binary(amount) and amount != "" ->
          recipe = get_recipe!(recipe_id)

          %ShoppingListContribution{}
          |> ShoppingListContribution.changeset(%{
            shopping_list_item_id: item.id,
            recipe_id: recipe.id,
            recipe_name: recipe.name,
            amount: amount
          })
          |> Repo.insert!()

        _ ->
          :ok
      end

      broadcast()
      get_shopping_list_item!(item.id)
    end)
  end

  defp get_or_create_open_item!(ingredient_id) do
    case Repo.get_by(ShoppingListItem, ingredient_id: ingredient_id, checked: false) do
      nil ->
        case %ShoppingListItem{} |> ShoppingListItem.changeset(%{ingredient_id: ingredient_id}) |> Repo.insert() do
          {:ok, item} ->
            item

          {:error, changeset} ->
            # Lost a race with a concurrent add for the same ingredient —
            # the partial unique index is the real guard here, this just
            # falls back to whichever row won instead of erroring.
            if Keyword.has_key?(changeset.errors, :ingredient_id) do
              Repo.get_by!(ShoppingListItem, ingredient_id: ingredient_id, checked: false)
            else
              raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
            end
        end

      item ->
        item
    end
  end

  def check_item(%ShoppingListItem{} = item) do
    item
    |> ShoppingListItem.changeset(%{checked: true, checked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
    |> tap_ok(fn _ -> broadcast() end)
  end

  def check_item(id) when is_binary(id), do: id |> get_shopping_list_item!() |> check_item()

  @doc """
  Unchecks an item. Merge-safe: if a newer open item for the same
  ingredient already exists (e.g. it was re-added after this one was
  checked off), this item's contributions move onto that open item and
  this row is deleted, rather than violating the one-open-item-per-
  ingredient invariant.
  """
  def uncheck_item(%ShoppingListItem{} = item) do
    Repo.transaction(fn ->
      case Repo.get_by(ShoppingListItem, ingredient_id: item.ingredient_id, checked: false) do
        nil ->
          {:ok, updated} =
            item |> ShoppingListItem.changeset(%{checked: false, checked_at: nil}) |> Repo.update()

          updated

        %ShoppingListItem{} = open_item ->
          from(c in ShoppingListContribution, where: c.shopping_list_item_id == ^item.id)
          |> Repo.update_all(set: [shopping_list_item_id: open_item.id])

          if is_nil(open_item.note) and not is_nil(item.note) do
            open_item |> ShoppingListItem.changeset(%{note: item.note}) |> Repo.update!()
          end

          Repo.delete!(item)
          open_item
      end
    end)
    |> tap_ok(fn _ -> broadcast() end)
  end

  def uncheck_item(id) when is_binary(id), do: id |> get_shopping_list_item!() |> uncheck_item()

  def update_shopping_list_item(%ShoppingListItem{} = item, attrs) do
    item |> ShoppingListItem.changeset(attrs) |> Repo.update() |> tap_ok(fn _ -> broadcast() end)
  end

  def delete_shopping_list_item(%ShoppingListItem{} = item) do
    Repo.delete(item) |> tap_ok(fn _ -> broadcast() end)
  end

  def delete_shopping_list_item(id) when is_binary(id) do
    id |> get_shopping_list_item!() |> delete_shopping_list_item()
  end

  def delete_contribution(%ShoppingListContribution{} = contribution) do
    Repo.delete(contribution) |> tap_ok(fn _ -> broadcast() end)
  end

  def delete_contribution(id) when is_binary(id) do
    id |> Repo.get!(ShoppingListContribution) |> delete_contribution()
  end

  @doc "Deletes every checked item (and its contributions, via cascade). Returns the count removed."
  def clear_checked_items do
    {count, _} = ShoppingListItem |> where([s], s.checked == true) |> Repo.delete_all()
    if count > 0, do: broadcast()
    count
  end

  defp stringify_keys(map) when is_map(map) or is_list(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result

  defp broadcast, do: SapoKit.PubSub.broadcast("recipes:shopping_list", :updated)
end
