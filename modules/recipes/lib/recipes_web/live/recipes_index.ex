defmodule RecipesWeb.Live.RecipesIndex do
  @moduledoc "Searchable recipe list."
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(query: "") |> load()}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(query: query) |> load()}
  end

  defp load(socket) do
    assign(socket, recipes: Recipes.list_recipes(socket.assigns.query))
  end

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

        <p :if={@recipes == [] and @query != ""} class="text-[#86948F] text-sm">
          No recipes match "{@query}".
        </p>

        <p :if={@recipes == [] and @query == ""} class="text-[#86948F] text-sm">
          No recipes yet.
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
