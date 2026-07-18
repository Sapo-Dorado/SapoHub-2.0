defmodule RecipesWeb.Api.RecipesController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Recipes.Recipe

  def index(conn, params) do
    json(conn, Enum.map(Recipes.list_recipes(params["q"]), &serialize_summary/1))
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize_detail(Recipes.get_recipe!(id)))
  end

  def create(conn, params) do
    case Recipes.create_recipe(params) do
      {:ok, recipe} ->
        conn |> put_status(:created) |> json(serialize_detail(Recipes.get_recipe!(recipe.id)))

      {:error, changeset} ->
        render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    recipe = Recipes.get_recipe!(id)

    case Recipes.update_recipe(recipe, Map.delete(params, "id")) do
      {:ok, recipe} -> json(conn, serialize_detail(Recipes.get_recipe!(recipe.id)))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = Recipes.delete_recipe(id)
    send_resp(conn, :no_content, "")
  end

  defp serialize_summary(%Recipe{} = r) do
    %{id: r.id, name: r.name, ingredient_count: length(r.recipe_ingredients)}
  end

  defp serialize_detail(%Recipe{} = r) do
    %{
      id: r.id,
      name: r.name,
      directions: r.directions,
      ingredients:
        r.recipe_ingredients
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn ri ->
          %{
            ingredient_id: ri.ingredient_id,
            ingredient_name: ri.ingredient.name,
            amount: ri.amount,
            position: ri.position
          }
        end),
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end
end
