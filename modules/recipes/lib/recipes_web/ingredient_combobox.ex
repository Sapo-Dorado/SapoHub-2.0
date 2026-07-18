defmodule RecipesWeb.IngredientCombobox do
  @moduledoc """
  Ingredient name entry: type to search registered ingredients, pick one,
  or create a new one from the current text. Shared verbatim between the
  shopping-list "add an item" bar and each ingredient row in the recipe
  form — the one place ingredient names get typed anywhere in this UI.

  Notifies the parent LiveView with `{:ingredient_combobox, id, ingredient}`
  when an ingredient is picked or created — LiveComponents run in their
  parent LiveView's process, so a plain `send(self(), ...)` reaches the
  parent's `handle_info/2` with no extra wiring.
  """
  use Phoenix.LiveComponent

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    # `:query` is deliberately NOT resynced from the caller on every
    # update — only seeded once, on this component's first mount (e.g. to
    # pre-fill an existing ingredient's name when editing a recipe).
    # Forwarding it unconditionally would clobber whatever the user is
    # mid-typing here every time the PARENT re-renders for an unrelated
    # reason (adding another row, a validation error round-trip, ...).
    initial_query = assigns[:query] || ""

    {:ok,
     socket
     |> assign(Map.delete(assigns, :query))
     |> assign_new(:query, fn -> initial_query end)
     |> assign_new(:open, fn -> false end)
     |> assign_new(:results, fn -> [] end)
     |> assign_new(:error, fn -> nil end)
     |> assign_new(:placeholder, fn -> "Ingredient name…" end)
     |> assign_new(:autofocus, fn -> false end)
     |> assign_new(:clear_on_select, fn -> true end)}
  end

  @impl true
  def handle_event("input", %{"value" => value}, socket) do
    results = if String.trim(value) == "", do: [], else: Recipes.list_ingredients(value)
    {:noreply, assign(socket, query: value, results: results, open: true, error: nil)}
  end

  def handle_event("focus", _params, socket) do
    {:noreply, assign(socket, open: true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("select_existing", %{"id" => ingredient_id}, socket) do
    ingredient = Recipes.get_ingredient!(ingredient_id)
    notify_parent(socket, ingredient)
    {:noreply, confirm(socket, ingredient)}
  end

  def handle_event("create", _params, socket) do
    name = String.trim(socket.assigns.query)

    case Recipes.create_ingredient(%{name: name}) do
      {:ok, ingredient} ->
        notify_parent(socket, ingredient)
        {:noreply, confirm(socket, ingredient)}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Name collided with an existing ingredient between typing and
        # clicking "create" — from the user's point of view they picked
        # an ingredient either way, so fall back to the existing one
        # rather than showing an error for what looks like success.
        case existing_exact_match(name) do
          nil ->
            {:noreply, assign(socket, error: changeset_error(changeset))}

          existing ->
            notify_parent(socket, existing)
            {:noreply, confirm(socket, existing)}
        end
    end
  end

  defp existing_exact_match(name) do
    name
    |> Recipes.list_ingredients()
    |> Enum.find(&(String.downcase(&1.name) == String.downcase(name)))
  end

  # After a pick, the input either clears (ready for the next entry — the
  # shopping-list "add an item" bar's semantics) or shows the confirmed
  # ingredient's name (the recipe-form row's semantics, so the row keeps
  # showing what it's set to) — see `:clear_on_select`.
  defp confirm(socket, ingredient) do
    query = if socket.assigns.clear_on_select, do: "", else: ingredient.name
    assign(socket, query: query, open: false, results: [], error: nil)
  end

  defp notify_parent(socket, ingredient) do
    send(self(), {:ingredient_combobox, socket.assigns.id, ingredient})
  end

  defp changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
  end

  defp show_create?(query, results) do
    trimmed = String.trim(query)
    trimmed != "" and not Enum.any?(results, &(String.downcase(&1.name) == String.downcase(trimmed)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" phx-click-away={JS.push("close", target: @myself)}>
      <input
        type="text"
        value={@query}
        placeholder={@placeholder}
        autocomplete="off"
        phx-hook={@autofocus && "ComboboxAutoFocus"}
        id={"#{@id}-input"}
        phx-keyup="input"
        phx-focus="focus"
        phx-target={@myself}
        class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-[12.5px] text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
      />

      <div
        :if={@open and (@results != [] or show_create?(@query, @results))}
        class="absolute top-[calc(100%+4px)] left-0 right-0 z-20 rounded-[4px] bg-[#151B1E] border border-[#242D31] overflow-hidden"
      >
        <button
          :for={ingredient <- @results}
          type="button"
          phx-click="select_existing"
          phx-value-id={ingredient.id}
          phx-target={@myself}
          class="block w-full text-left px-3 py-[7px] font-mono text-[12px] text-[#E6ECE9] hover:bg-[#0D1113] cursor-pointer"
        >
          {ingredient.name}
        </button>

        <button
          :if={show_create?(@query, @results)}
          type="button"
          phx-click="create"
          phx-target={@myself}
          class="block w-full text-left px-3 py-[7px] font-mono text-[12px] text-[#7FB069] hover:bg-[#0D1113] cursor-pointer border-t border-[#242D31]"
        >
          + create "{String.trim(@query)}"
        </button>
      </div>

      <p :if={@error} class="mt-1 font-mono text-[11px] text-[#C1594A]">{@error}</p>
    </div>
    """
  end
end
