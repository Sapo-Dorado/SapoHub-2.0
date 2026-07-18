defmodule Recipes.Module do
  @moduledoc """
  SapoKit.Module implementation for Recipes: a shared shopping list fed
  by registered ingredients and recipes. See `docs/module-authoring.md`
  and `Recipes` (the context) for the full design.
  """
  use SapoKit.Module

  @impl true
  def id, do: :recipes

  @impl true
  def title, do: "Recipes"

  @impl true
  def icon, do: "hero-shopping-cart"

  @impl true
  def statusline_items(_config) do
    [
      %SapoKit.StatuslineItem{
        id: "recipes.shopping_list",
        label: "Shopping list",
        text: fn ->
          case Recipes.count_open_shopping_list_items() do
            0 -> "list empty"
            n -> "#{n} to get"
          end
        end,
        level: fn -> if Recipes.count_open_shopping_list_items() > 0, do: :ok, else: :neutral end,
        topics: ["recipes:shopping_list"]
      }
    ]
  end

  @impl true
  def ui_routes do
    [
      # First route = the default dashboard button's target — the shopping
      # list is the main view per the module's brief, recipes/ingredients
      # are reached from within it.
      %{path: "/shopping-list", live_view: RecipesWeb.Live.ShoppingList, action: :index},
      %{path: "/recipes", live_view: RecipesWeb.Live.RecipesIndex, action: :index},
      %{path: "/recipes/new", live_view: RecipesWeb.Live.RecipeForm, action: :new},
      %{path: "/recipes/ingredients", live_view: RecipesWeb.Live.Ingredients, action: :index},
      %{path: "/recipes/:id", live_view: RecipesWeb.Live.RecipeShow, action: :show},
      %{path: "/recipes/:id/edit", live_view: RecipesWeb.Live.RecipeForm, action: :edit}
    ]
  end

  @impl true
  def api_routes do
    alias RecipesWeb.Api

    [
      %{verb: :get, path: "/recipes/ingredients", controller: Api.IngredientsController, action: :index},
      %{verb: :post, path: "/recipes/ingredients", controller: Api.IngredientsController, action: :create},
      %{verb: :patch, path: "/recipes/ingredients/:id", controller: Api.IngredientsController, action: :update},
      %{verb: :delete, path: "/recipes/ingredients/:id", controller: Api.IngredientsController, action: :delete},
      %{verb: :get, path: "/recipes/shopping-list", controller: Api.ShoppingListController, action: :index},
      %{verb: :post, path: "/recipes/shopping-list/items", controller: Api.ShoppingListController, action: :create},
      %{
        verb: :patch,
        path: "/recipes/shopping-list/items/:id",
        controller: Api.ShoppingListController,
        action: :update
      },
      %{
        verb: :post,
        path: "/recipes/shopping-list/items/:id/check",
        controller: Api.ShoppingListController,
        action: :check
      },
      %{
        verb: :post,
        path: "/recipes/shopping-list/items/:id/uncheck",
        controller: Api.ShoppingListController,
        action: :uncheck
      },
      %{
        verb: :delete,
        path: "/recipes/shopping-list/items/:id",
        controller: Api.ShoppingListController,
        action: :delete
      },
      %{
        verb: :delete,
        path: "/recipes/shopping-list/contributions/:id",
        controller: Api.ShoppingListController,
        action: :delete_contribution
      },
      %{
        verb: :delete,
        path: "/recipes/shopping-list/checked",
        controller: Api.ShoppingListController,
        action: :clear_checked
      },
      %{verb: :get, path: "/recipes", controller: Api.RecipesController, action: :index},
      %{verb: :post, path: "/recipes", controller: Api.RecipesController, action: :create},
      %{verb: :get, path: "/recipes/:id", controller: Api.RecipesController, action: :show},
      %{verb: :patch, path: "/recipes/:id", controller: Api.RecipesController, action: :update},
      %{verb: :delete, path: "/recipes/:id", controller: Api.RecipesController, action: :delete}
    ]
  end

  @impl true
  def ai_context do
    ingredients = length(Recipes.list_ingredients())
    recipes = length(Recipes.list_recipes())
    open = Recipes.count_open_shopping_list_items()

    """
    Recipes tracks a shared shopping list fed by registered ingredients and
    recipes. #{recipes} recipe(s), #{ingredients} registered ingredient(s),
    #{open} item(s) currently on the shopping list.

    Ingredients are a name registry — amounts are always freeform text
    attached to a recipe-ingredient line or a shopping-list contribution,
    never structured units. Adding an ingredient to the shopping list from a
    recipe records which recipe and how much; the same ingredient added from
    multiple recipes shows each recipe's amount separately rather than
    combining them.

    Use `sapo recipes ...` / `sapo ingredients ...` / `sapo shopping-list ...`
    or the /api/recipes, /api/recipes/ingredients, and
    /api/recipes/shopping-list endpoints.
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    Recipes manages a shopping list plus registered recipes/ingredients
    (`sapo shopping-list`, `sapo recipes`, `sapo ingredients`). If the user
    mentions needing to buy something, offer to add it to the shopping list;
    if they mention a dish they cooked or want to save, offer to save it as
    a recipe.
    """
  end
end
