defmodule RecipesWeb.Api.IngredientsController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Recipes.Ingredient

  def index(conn, params) do
    json(conn, Enum.map(Recipes.list_ingredients(params["q"]), &serialize/1))
  end

  def create(conn, params) do
    case Recipes.create_ingredient(params) do
      {:ok, ingredient} -> conn |> put_status(:created) |> json(serialize(ingredient))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    ingredient = Recipes.get_ingredient!(id)

    case Recipes.update_ingredient(ingredient, Map.delete(params, "id")) do
      {:ok, ingredient} -> json(conn, serialize(ingredient))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Recipes.delete_ingredient(id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :in_use} ->
        usage = Recipes.ingredient_usage(id)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "ingredient is still in use",
          recipes: usage.recipes,
          shopping_list: usage.shopping_list
        })
    end
  end

  defp serialize(%Ingredient{} = i) do
    %{id: i.id, name: i.name, inserted_at: i.inserted_at}
  end
end
