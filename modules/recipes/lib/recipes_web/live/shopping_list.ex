defmodule RecipesWeb.Live.ShoppingList do
  @moduledoc """
  The module's main view: the shared shopping list, open items first,
  checked items collapsed below. Items can be added directly here (via
  the shared `RecipesWeb.IngredientCombobox`) or from a recipe's ingredient
  list (`RecipesWeb.Live.RecipeShow`) — either path lands here.
  """
  use SapoKit.Web, :live_view

  alias RecipesWeb.IngredientCombobox

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("recipes:shopping_list")
    {:ok, load(socket)}
  end

  @impl true
  def handle_event("toggle_checked", %{"id" => id}, socket) do
    item = Recipes.get_shopping_list_item!(id)
    if item.checked, do: Recipes.uncheck_item(item), else: Recipes.check_item(item)
    {:noreply, load(socket)}
  end

  def handle_event("update_note", %{"item_id" => id, "note" => note}, socket) do
    item = Recipes.get_shopping_list_item!(id)
    Recipes.update_shopping_list_item(item, %{"note" => note})
    {:noreply, load(socket)}
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    Recipes.delete_shopping_list_item(id)
    {:noreply, load(socket)}
  end

  def handle_event("remove_contribution", %{"id" => id}, socket) do
    Recipes.delete_contribution(id)
    {:noreply, load(socket)}
  end

  def handle_event("clear_checked", _params, socket) do
    Recipes.clear_checked_items()
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:ingredient_combobox, "shopping-list-add", ingredient}, socket) do
    Recipes.add_to_shopping_list(ingredient.id)
    {:noreply, load(socket)}
  end

  def handle_info(:updated, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    %{open: open, checked: checked} = Recipes.list_shopping_list_items()
    assign(socket, open: open, checked: checked)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="shopping-list" items={@statusline} right={"#{length(@open)} open"} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-5">
        <div class="flex items-center gap-2.5">
          <div class="flex items-center gap-2.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            shopping list
          </div>
          <span class="h-px flex-1 bg-[#242D31]"></span>
          <.link
            navigate="/recipes"
            class="flex items-center gap-1.5 px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            ↻ recipes
          </.link>
        </div>

        <.live_component
          module={IngredientCombobox}
          id="shopping-list-add"
          placeholder="+ add an item…"
        />

        <section :if={@open != []}>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            to get
            <span class="h-px flex-1 bg-[#242D31]"></span>
          </div>

          <ul class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
            <.item_row :for={item <- @open} item={item} />
          </ul>
        </section>

        <p :if={@open == [] and @checked == []} class="text-[#86948F] text-sm">
          Nothing on your list. Add an item above, or swipe an ingredient in a recipe.
        </p>

        <section :if={@checked != []}>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            checked off ({length(@checked)})
            <span class="h-px flex-1 bg-[#242D31]"></span>
            <button phx-click="clear_checked" class="normal-case tracking-normal text-[#7FB069] hover:text-[#8fbf7b] cursor-pointer">
              clear
            </button>
          </div>

          <ul class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E] opacity-60">
            <.item_row :for={item <- @checked} item={item} />
          </ul>
        </section>
      </main>
    </div>
    """
  end

  attr :item, :map, required: true

  defp item_row(assigns) do
    ~H"""
    <li class="flex items-start gap-3 px-3 py-3">
      <button
        phx-click="toggle_checked"
        phx-value-id={@item.id}
        aria-label={if @item.checked, do: "Uncheck item", else: "Check off item"}
        class={[
          "mt-0.5 w-[17px] h-[17px] shrink-0 rounded-full border-[1.5px] cursor-pointer",
          @item.checked && "bg-[#7FB069] border-[#7FB069]",
          !@item.checked && "border-[#5B7A8C] hover:border-[#7FB069]"
        ]}
      >
      </button>

      <div class="flex-1 min-w-0">
        <span class={["text-sm", @item.checked && "text-[#86948F] line-through"]}>
          {@item.ingredient.name}
        </span>

        <form :if={!@item.checked} phx-change="update_note" class="mt-0.5">
          <input type="hidden" name="item_id" value={@item.id} />
          <input
            type="text"
            name="note"
            value={@item.note}
            placeholder="add a note…"
            autocomplete="off"
            class="w-full bg-transparent border-none p-0 font-mono text-[11px] text-[#86948F] placeholder-[#4A5458] italic focus:outline-none focus:text-[#E6ECE9]"
          />
        </form>

        <div :if={@item.contributions != []} class="mt-1.5 flex flex-col gap-1">
          <div :for={c <- @item.contributions} class="flex items-center gap-1.5 font-mono text-[10.5px] text-[#86948F]">
            <span class="text-[#E6ECE9]">{c.amount}</span>
            <span>· {c.recipe_name}</span>
            <button
              phx-click="remove_contribution"
              phx-value-id={c.id}
              aria-label={"Remove #{c.recipe_name}'s amount"}
              class="text-[#4A5458] hover:text-[#C1594A] cursor-pointer"
            >
              ×
            </button>
          </div>
        </div>
      </div>

      <button
        phx-click="delete_item"
        phx-value-id={@item.id}
        aria-label="Remove from list"
        class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
      >
        ×
      </button>
    </li>
    """
  end
end
