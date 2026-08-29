defmodule RecipesWeb.Live.RecipesIndex do
  @moduledoc "Searchable recipe list, with an advanced filter by ingredient."
  use SapoKit.Web, :live_view

  alias RecipesWeb.IngredientCombobox

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(query: "", advanced_open: false, ingredient_id: nil, ingredient_name: nil, ingredient_combobox_key: 0)
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(query: query) |> load()}
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, advanced_open: !socket.assigns.advanced_open)}
  end

  def handle_event("clear_ingredient_filter", _params, socket) do
    socket =
      socket
      # Bumping the combobox's id forces a fresh mount (clearing its
      # internal query text) since IngredientCombobox never resyncs
      # :query from the parent after its first mount.
      |> assign(ingredient_id: nil, ingredient_name: nil, ingredient_combobox_key: socket.assigns.ingredient_combobox_key + 1)
      |> load()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ingredient_combobox, _id, ingredient}, socket) do
    socket = socket |> assign(ingredient_id: ingredient.id, ingredient_name: ingredient.name) |> load()
    {:noreply, socket}
  end

  defp load(socket) do
    assign(socket, recipes: Recipes.list_recipes(socket.assigns.query, socket.assigns.ingredient_id))
  end

  defp empty_message("", nil), do: ~s(No recipes yet.)
  defp empty_message(query, nil), do: ~s(No recipes match "#{query}".)
  defp empty_message("", ingredient_name), do: ~s(No recipes contain "#{ingredient_name}".)
  defp empty_message(query, ingredient_name), do: ~s(No recipes match "#{query}" containing "#{ingredient_name}".)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="recipes" items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-5">
        <div class="flex items-center gap-2.5">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            recipes
          </div>
          <span class="h-px flex-1 bg-[#242D31]"></span>
          <.link
            navigate="/shopping-list"
            class="flex items-center gap-1.5 px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            shopping list
          </.link>
        </div>

        <form phx-change="search">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="search recipes…"
            autocomplete="off"
            class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </form>

        <div class="rounded-[4px] border border-[#242D31] bg-[#151B1E]">
          <button
            type="button"
            phx-click="toggle_advanced"
            class="w-full flex items-center justify-between px-3 py-[9px] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
          >
            <span>advanced search</span>
            <span class={["transition-transform", @advanced_open && "rotate-180"]}>⌄</span>
          </button>

          <div :if={@advanced_open} class="px-3 pb-3 pt-1 border-t border-[#242D31] space-y-1.5">
            <label class="block font-mono text-[10.5px] font-semibold uppercase tracking-[.1em] text-[#86948F]">
              contains ingredient
            </label>
            <div class="flex items-center gap-2">
              <div class="flex-1 min-w-0">
                <.live_component
                  module={IngredientCombobox}
                  id={"search-ingredient-#{@ingredient_combobox_key}"}
                  placeholder="e.g. eggs…"
                  clear_on_select={false}
                />
              </div>
              <button
                :if={@ingredient_id}
                type="button"
                phx-click="clear_ingredient_filter"
                aria-label="Clear ingredient filter"
                class="shrink-0 font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
              >
                ×
              </button>
            </div>
          </div>
        </div>

        <ul :if={@recipes != []} class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
          <li :for={recipe <- @recipes}>
            <.link navigate={"/recipes/#{recipe.id}"} class="flex items-center gap-3 px-3 py-3 hover:bg-[#0D1113]">
              <div class="flex-1 min-w-0">
                <div class="text-sm truncate">{recipe.name}</div>
                <div class="font-mono text-[10.5px] text-[#86948F]">
                  {length(recipe.recipe_ingredients)} ingredient{if length(recipe.recipe_ingredients) != 1, do: "s"}
                </div>
              </div>
              <span class="text-[#86948F]">›</span>
            </.link>
          </li>
        </ul>

        <p :if={@recipes == []} class="text-[#86948F] text-sm">
          {empty_message(@query, @ingredient_name)}
        </p>

        <.link
          navigate="/recipes/new"
          class="block text-center px-3 py-[9px] rounded-[4px] border border-dashed border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer"
        >
          + new recipe
        </.link>

        <.link
          navigate="/recipes/ingredients"
          class="block text-center font-mono text-[10.5px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
        >
          manage ingredients →
        </.link>
      </main>
    </div>
    """
  end
end
