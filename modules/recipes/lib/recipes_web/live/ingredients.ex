defmodule RecipesWeb.Live.Ingredients do
  @moduledoc """
  The only place to fix a typo'd ingredient or remove an unused one —
  everywhere else in the UI only ever *creates* ingredients (via the
  combobox's "create new" flow). Delete is refused when a recipe or the
  shopping list still references the ingredient, same guard as the API
  (`Recipes.delete_ingredient/1`).
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(query: "", editing_id: nil) |> load()}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(query: query) |> load()}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("save_edit", %{"ingredient_id" => id, "name" => name}, socket) do
    ingredient = Recipes.get_ingredient!(id)

    socket =
      case Recipes.update_ingredient(ingredient, %{"name" => name}) do
        {:ok, _} -> socket |> assign(editing_id: nil) |> put_flash(:info, nil)
        {:error, changeset} -> put_flash(socket, :error, changeset_error(changeset))
      end

    {:noreply, load(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      case Recipes.delete_ingredient(id) do
        {:ok, _} ->
          socket

        {:error, :in_use} ->
          put_flash(socket, :error, "Still used elsewhere — remove it from those recipes or the shopping list first.")
      end

    {:noreply, load(socket)}
  end

  defp load(socket) do
    ingredients =
      socket.assigns.query
      |> Recipes.list_ingredients()
      |> Enum.map(fn ingredient -> %{ingredient: ingredient, usage: Recipes.ingredient_usage(ingredient.id)} end)

    assign(socket, ingredients: ingredients)
  end

  defp changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="recipes / ingredients" items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-5">
        <div class="flex items-center gap-2.5">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            ingredients
          </div>
          <span class="h-px flex-1 bg-[#242D31]"></span>
          <.link
            navigate="/recipes"
            class="flex items-center gap-1.5 px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            ‹ recipes
          </.link>
        </div>

        <form phx-change="search">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="search ingredients…"
            autocomplete="off"
            class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </form>

        <ul :if={@ingredients != []} class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
          <li :for={%{ingredient: ingredient, usage: usage} <- @ingredients} class="flex items-center gap-3 px-3 py-2.5">
            <div class="flex-1 min-w-0">
              <form :if={@editing_id == ingredient.id} phx-submit="save_edit" class="flex items-center gap-2">
                <input type="hidden" name="ingredient_id" value={ingredient.id} />
                <input
                  type="text"
                  name="name"
                  value={ingredient.name}
                  autocomplete="off"
                  autofocus
                  class="min-w-0 box-border px-2 py-1 rounded-[4px] bg-[#0D1113] border border-[#7FB069] text-sm text-[#E6ECE9] focus:outline-none font-mono"
                />
                <button type="submit" class="font-mono text-[#7FB069] hover:text-[#8fbf7b] cursor-pointer">✓</button>
                <button type="button" phx-click="cancel_edit" class="font-mono text-[#86948F] hover:text-[#E6ECE9] cursor-pointer">
                  cancel
                </button>
              </form>

              <div :if={@editing_id != ingredient.id}>
                <div class="text-sm truncate">{ingredient.name}</div>
                <div class="font-mono text-[10.5px] text-[#86948F]">
                  used in {usage.recipes} recipe{if usage.recipes != 1, do: "s"}
                </div>
              </div>
            </div>

            <div :if={@editing_id != ingredient.id} class="flex items-center gap-3 shrink-0">
              <button
                phx-click="start_edit"
                phx-value-id={ingredient.id}
                aria-label={"Rename #{ingredient.name}"}
                class="font-mono text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
              >
                ✎
              </button>
              <button
                :if={usage.recipes == 0 and usage.shopping_list == 0}
                phx-click="delete"
                phx-value-id={ingredient.id}
                aria-label={"Delete #{ingredient.name}"}
                class="font-mono text-[#86948F] hover:text-[#C1594A] cursor-pointer"
              >
                ×
              </button>
              <span
                :if={usage.recipes > 0 or usage.shopping_list > 0}
                title="Still referenced by a recipe or the shopping list — remove it from those first"
                class="font-mono text-[#3A4448] cursor-not-allowed"
              >
                ×
              </span>
            </div>
          </li>
        </ul>

        <p :if={@ingredients == [] and @query != ""} class="text-[#86948F] text-sm">
          No ingredients match "{@query}".
        </p>

        <p :if={@ingredients == [] and @query == ""} class="text-[#86948F] text-sm">
          No ingredients registered yet — they're created inline wherever you type an ingredient name.
        </p>
      </main>
    </div>
    """
  end
end
