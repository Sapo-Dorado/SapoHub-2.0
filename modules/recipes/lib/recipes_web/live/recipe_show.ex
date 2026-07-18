defmodule RecipesWeb.Live.RecipeShow do
  @moduledoc """
  A recipe's directions and ingredient list. Each ingredient row can be
  swiped (via the `SwipeToAdd` JS hook) or tapped (the persistent circle
  button — swipe is an accelerator, never the only way in) to add it to
  the shopping list, carrying this recipe's name and that line's amount
  along as a `Recipes.ShoppingListContribution`.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(confirm_delete: false) |> load(id)}
  end

  @impl true
  def handle_event("add_ingredient", %{"id" => recipe_ingredient_id}, socket) do
    ri = Enum.find(socket.assigns.recipe.recipe_ingredients, &(&1.id == recipe_ingredient_id))

    if ri do
      Recipes.add_to_shopping_list(ri.ingredient_id, %{
        "recipe_id" => socket.assigns.recipe.id,
        "amount" => ri.amount || ""
      })
    end

    {:noreply, push_event(socket, "ingredient_added", %{id: recipe_ingredient_id})}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: false)}
  end

  def handle_event("delete_recipe", _params, socket) do
    {:ok, _} = Recipes.delete_recipe(socket.assigns.recipe.id)
    {:noreply, push_navigate(socket, to: "/recipes")}
  end

  defp load(socket, id) do
    recipe = Recipes.get_recipe!(id)
    ingredients = Enum.sort_by(recipe.recipe_ingredients, & &1.position)
    assign(socket, recipe: recipe, ingredients: ingredients)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <style>
        /* Swiping left on a row (SwipeToAdd hook, hooks.js) reveals this
           sage background behind the front card as it translates. */
        .recipes-swipe-row { position: relative; overflow: hidden; border-radius: 4px; }
        .recipes-swipe-reveal {
          position: absolute; inset: 0; display: flex; align-items: center; justify-content: flex-end;
          padding-right: 16px; background: #7FB069; color: #0C1409;
          font-family: ui-monospace, monospace; font-size: 11px; font-weight: 600;
        }
        /* Brief confirmation flash after an add, whether triggered by swipe
           or the plain tap button (hooks.js fires this on "ingredient_added"). */
        .recipes-row-added-flash [data-swipe-front] { border-color: #7FB069 !important; transition: border-color 150ms ease-out; }
      </style>

      <SapoCoreWeb.Statusline.statusline crumb={@recipe.name} items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-5">
        <div class="flex items-center justify-between">
          <.link navigate="/recipes" class="font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9]">
            ‹ recipes
          </.link>
          <div class="flex items-center gap-2">
            <.link
              navigate={"/recipes/#{@recipe.id}/edit"}
              class="px-3 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
            >
              edit
            </.link>
            <button
              :if={!@confirm_delete}
              phx-click="confirm_delete"
              class="px-3 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[11px] text-[#86948F] hover:text-[#E0A458] hover:border-[#3C5934] cursor-pointer"
            >
              delete
            </button>
            <span :if={@confirm_delete} class="flex items-center gap-2 font-mono text-[11px]">
              <span class="text-[#E0A458]">delete this recipe?</span>
              <button phx-click="cancel_delete" class="text-[#86948F] hover:text-[#E6ECE9] cursor-pointer">cancel</button>
              <button phx-click="delete_recipe" class="text-[#C1594A] hover:text-[#d4715f] cursor-pointer">delete</button>
            </span>
          </div>
        </div>

        <h1 class="text-xl font-semibold">{@recipe.name}</h1>

        <section>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            ingredients
            <span class="h-px flex-1 bg-[#242D31]"></span>
          </div>

          <div class="space-y-2">
            <div
              :for={ri <- @ingredients}
              id={"recipe-ingredient-#{ri.id}"}
              phx-hook="SwipeToAdd"
              data-id={ri.id}
              class="recipes-swipe-row"
            >
              <div class="recipes-swipe-reveal">add ✓</div>
              <div
                data-swipe-front
                class="relative flex items-center justify-between gap-3 px-3 py-3 rounded-[4px] border border-[#242D31] bg-[#151B1E]"
              >
                <div class="min-w-0">
                  <div class="text-sm">{ri.ingredient.name}</div>
                  <div :if={ri.amount not in [nil, ""]} class="font-mono text-[10.5px] text-[#86948F]">{ri.amount}</div>
                </div>
                <button
                  phx-click="add_ingredient"
                  phx-value-id={ri.id}
                  aria-label={"Add #{ri.ingredient.name} to shopping list"}
                  class="shrink-0 w-[24px] h-[24px] rounded-full border-[1.5px] border-[#242D31] text-[#86948F] hover:border-[#7FB069] hover:text-[#7FB069] cursor-pointer"
                >
                  +
                </button>
              </div>
            </div>
          </div>

          <p class="mt-2 text-center font-mono text-[10px] text-[#86948F]">
            ← swipe an ingredient to add it, or tap the circle
          </p>
        </section>

        <section>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            directions
            <span class="h-px flex-1 bg-[#242D31]"></span>
          </div>

          <div class="rounded-[4px] border border-[#242D31] bg-[#151B1E] px-3 py-3 text-[13px] leading-relaxed whitespace-pre-wrap">{@recipe.directions}</div>
        </section>
      </main>
    </div>
    """
  end
end
