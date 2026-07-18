defmodule RecipesWeb.Live.RecipeForm do
  @moduledoc """
  Create/edit a recipe: name, directions, and a dynamic list of ingredient
  rows, each pairing the shared `RecipesWeb.IngredientCombobox` with a
  freeform amount field. Ingredient identity lives in server assigns
  (`rows`), keyed by a per-row key; only each row's amount travels through
  the actual `<form>` submission — see `save/2` for how the two combine.
  """
  use SapoKit.Web, :live_view

  alias RecipesWeb.IngredientCombobox

  @impl true
  def mount(params, _session, socket) do
    socket =
      case socket.assigns.live_action do
        :new ->
          assign(socket, recipe_id: nil, name: "", directions: "", rows: [empty_row()])

        :edit ->
          recipe = Recipes.get_recipe!(params["id"])

          rows =
            recipe.recipe_ingredients
            |> Enum.sort_by(& &1.position)
            |> Enum.map(fn ri ->
              %{key: "row-#{ri.id}", ingredient_id: ri.ingredient_id, ingredient_name: ri.ingredient.name, amount: ri.amount}
            end)

          assign(socket, recipe_id: recipe.id, name: recipe.name, directions: recipe.directions, rows: rows)
      end

    {:ok, assign(socket, error: nil)}
  end

  defp empty_row, do: %{key: "row-#{System.unique_integer([:positive])}", ingredient_id: nil, ingredient_name: "", amount: ""}

  @impl true
  def handle_event("validate", %{"name" => name, "directions" => directions} = params, socket) do
    amounts = params["ingredients"] || %{}

    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case get_in(amounts, [row.key, "amount"]) do
          nil -> row
          amount -> %{row | amount: amount}
        end
      end)

    {:noreply, assign(socket, name: name, directions: directions, rows: rows)}
  end

  def handle_event("add_row", _params, socket) do
    {:noreply, assign(socket, rows: socket.assigns.rows ++ [empty_row()])}
  end

  def handle_event("remove_row", %{"key" => key}, socket) do
    {:noreply, assign(socket, rows: Enum.reject(socket.assigns.rows, &(&1.key == key)))}
  end

  def handle_event("save", %{"name" => name, "directions" => directions} = params, socket) do
    amounts = params["ingredients"] || %{}

    ingredients =
      socket.assigns.rows
      |> Enum.filter(& &1.ingredient_id)
      |> Enum.map(fn row ->
        %{"ingredient_id" => row.ingredient_id, "amount" => get_in(amounts, [row.key, "amount"]) || row.amount || ""}
      end)

    attrs = %{"name" => name, "directions" => directions, "ingredients" => ingredients}

    result =
      case socket.assigns.recipe_id do
        nil -> Recipes.create_recipe(attrs)
        id -> Recipes.update_recipe(Recipes.get_recipe!(id), attrs)
      end

    case result do
      {:ok, recipe} ->
        {:noreply, push_navigate(socket, to: "/recipes/#{recipe.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, error: format_changeset_error(changeset))}
    end
  end

  @impl true
  def handle_info({:ingredient_combobox, key, ingredient}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn
        %{key: ^key} = row -> %{row | ingredient_id: ingredient.id, ingredient_name: ingredient.name}
        row -> row
      end)

    # Selecting/creating an ingredient in the last empty row implicitly
    # opens a fresh one, so the list never runs out of room to keep adding.
    rows = if rows != [] and List.last(rows).ingredient_id, do: rows ++ [empty_row()], else: rows

    {:noreply, assign(socket, rows: rows)}
  end

  defp format_changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb={if @recipe_id, do: "recipes / edit", else: "recipes / new"} items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-5">
        <.link navigate="/recipes" class="font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9]">
          ‹ recipes
        </.link>

        <h1 class="text-xl font-semibold">{if @recipe_id, do: "Edit recipe", else: "New recipe"}</h1>

        <p :if={@error} class="font-mono text-[12px] text-[#C1594A]">{@error}</p>

        <form phx-submit="save" phx-change="validate" class="space-y-5">
          <div>
            <label class="block font-mono text-[10.5px] font-semibold uppercase tracking-[.1em] text-[#86948F] mb-1.5">
              name
            </label>
            <input
              type="text"
              name="name"
              value={@name}
              placeholder="Recipe name…"
              autocomplete="off"
              required
              class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
            />
          </div>

          <div>
            <label class="block font-mono text-[10.5px] font-semibold uppercase tracking-[.1em] text-[#86948F] mb-1.5">
              ingredients
            </label>

            <div class="space-y-2">
              <div :for={row <- @rows} class="flex gap-2 items-start">
                <div class="flex-1 min-w-0">
                  <.live_component
                    module={IngredientCombobox}
                    id={row.key}
                    query={row.ingredient_name}
                    placeholder="Ingredient name…"
                    clear_on_select={false}
                  />
                </div>
                <input
                  type="text"
                  name={"ingredients[#{row.key}][amount]"}
                  value={row.amount}
                  placeholder="amount"
                  autocomplete="off"
                  class="w-[100px] shrink-0 box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
                />
                <button
                  type="button"
                  phx-click="remove_row"
                  phx-value-key={row.key}
                  aria-label="Remove ingredient row"
                  class="mt-2 font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
                >
                  ×
                </button>
              </div>
            </div>

            <button
              type="button"
              phx-click="add_row"
              class="mt-2 w-full px-3 py-[7px] rounded-[4px] border border-dashed border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer"
            >
              + add ingredient
            </button>
          </div>

          <div>
            <label class="block font-mono text-[10.5px] font-semibold uppercase tracking-[.1em] text-[#86948F] mb-1.5">
              directions
            </label>
            <textarea
              name="directions"
              rows="6"
              placeholder="What to do…"
              class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono resize-y"
            >{@directions}</textarea>
          </div>

          <div class="flex items-center justify-end gap-2">
            <.link
              navigate={if @recipe_id, do: "/recipes/#{@recipe_id}", else: "/recipes"}
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
            >
              Cancel
            </.link>
            <button
              type="submit"
              class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
            >
              {if @recipe_id, do: "Save", else: "Create"}
            </button>
          </div>
        </form>
      </main>
    </div>
    """
  end
end
