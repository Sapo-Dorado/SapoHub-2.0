defmodule RecipesWeb.Api.ShoppingListController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Recipes.ShoppingListItem

  def index(conn, _params) do
    %{open: open, checked: checked} = Recipes.list_shopping_list_items()
    json(conn, %{open: Enum.map(open, &serialize/1), checked: Enum.map(checked, &serialize/1)})
  end

  @doc """
  Unified add: upserts the open item for `ingredient_id`, optionally
  appending a recipe contribution (`recipe_id` + `amount`) and/or setting
  the item's freeform `note`. See `Recipes.add_to_shopping_list/2`.
  """
  def create(conn, %{"ingredient_id" => ingredient_id} = params) do
    case Recipes.add_to_shopping_list(ingredient_id, Map.delete(params, "ingredient_id")) do
      {:ok, item} -> conn |> put_status(:created) |> json(serialize(item))
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    item = Recipes.get_shopping_list_item!(id)

    with {:ok, item} <- maybe_update_note(item, params["note"]),
         {:ok, item} <- maybe_update_checked(item, params["checked"]) do
      json(conn, serialize(Recipes.get_shopping_list_item!(item.id)))
    else
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  defp maybe_update_note(item, nil), do: {:ok, item}
  defp maybe_update_note(item, note), do: Recipes.update_shopping_list_item(item, %{"note" => note})

  defp maybe_update_checked(item, nil), do: {:ok, item}
  defp maybe_update_checked(item, true), do: Recipes.check_item(item)
  defp maybe_update_checked(item, false), do: Recipes.uncheck_item(item)

  def delete(conn, %{"id" => id}) do
    {:ok, _} = Recipes.delete_shopping_list_item(id)
    send_resp(conn, :no_content, "")
  end

  def check(conn, %{"id" => id}) do
    {:ok, item} = Recipes.check_item(id)
    json(conn, serialize(Recipes.get_shopping_list_item!(item.id)))
  end

  def uncheck(conn, %{"id" => id}) do
    {:ok, item} = Recipes.uncheck_item(id)
    json(conn, serialize(Recipes.get_shopping_list_item!(item.id)))
  end

  def delete_contribution(conn, %{"id" => id}) do
    {:ok, _} = Recipes.delete_contribution(id)
    send_resp(conn, :no_content, "")
  end

  def clear_checked(conn, _params) do
    count = Recipes.clear_checked_items()
    json(conn, %{cleared: count})
  end

  defp serialize(%ShoppingListItem{} = item) do
    %{
      id: item.id,
      ingredient_id: item.ingredient_id,
      ingredient_name: item.ingredient.name,
      note: item.note,
      checked: item.checked,
      checked_at: item.checked_at,
      contributions:
        Enum.map(item.contributions, fn c ->
          %{id: c.id, recipe_id: c.recipe_id, recipe_name: c.recipe_name, amount: c.amount}
        end)
    }
  end
end
