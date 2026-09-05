defmodule SubscriptionsWeb.Live.Index do
  @moduledoc """
  The module's only view: an "+ add subscription" button opens a modal
  (matching the amex_rewards module's add-expense pattern), then
  subscriptions grouped by billing cadence (each group showing a monthly
  subtotal), under a grand-total-monthly-cost banner. Editing an existing
  subscription turns its row into the same field set inline (`@editing_id`)
  rather than navigating to a separate page — there's not enough here to
  justify one.
  """
  use SapoKit.Web, :live_view

  alias Subscriptions.Subscription

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("subscriptions:list")

    {:ok,
     socket
     |> assign(
       editing_id: nil,
       edit_error: nil,
       edit_form: nil,
       show_add_modal: false,
       create_error: nil,
       form_key: 0
     )
     |> load()}
  end

  defp load(socket) do
    assign(socket, summary: Subscriptions.grouped_summary())
  end

  @impl true
  def handle_event("open_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: true, create_error: nil)}
  end

  def handle_event("close_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, create_error: nil)}
  end

  def handle_event("create", %{"subscription" => params}, socket) do
    case Subscriptions.create_subscription(params) do
      {:ok, _subscription} ->
        {:noreply,
         socket
         |> assign(create_error: nil, show_add_modal: false)
         |> update(:form_key, &(&1 + 1))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, create_error: format_changeset_error(changeset))}
    end
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    subscription = Subscriptions.get_subscription!(id)
    {:noreply, assign(socket, editing_id: id, edit_error: nil, edit_form: edit_form(subscription))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_error: nil)}
  end

  def handle_event("save_edit", %{"subscription" => params}, socket) do
    subscription = Subscriptions.get_subscription!(socket.assigns.editing_id)

    case Subscriptions.update_subscription(subscription, params) do
      {:ok, _subscription} ->
        {:noreply, socket |> assign(editing_id: nil, edit_error: nil) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_error: format_changeset_error(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Subscriptions.delete_subscription(id)
    {:noreply, socket |> assign(editing_id: nil) |> load()}
  end

  @impl true
  def handle_info(:updated, socket), do: {:noreply, load(socket)}

  defp edit_form(%Subscription{} = s) do
    %{
      "name" => s.name,
      "cost" => dollars(s.cost_cents),
      "interval_count" => to_string(s.interval_count),
      "interval_unit" => s.interval_unit
    }
  end

  defp format_changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  defp money(cents), do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
  defp dollars(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)

  attr :title, :string, required: true
  attr :close_event, :string, required: true
  slot :inner_block, required: true
  slot :actions, required: true

  defp modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60"
      phx-window-keydown={@close_event}
      phx-key="Escape"
    >
      <div
        class="w-full max-w-[420px] rounded-[6px] border border-[#242D31] bg-[#151B1E] shadow-2xl"
        phx-click-away={@close_event}
      >
        <div class="px-4 py-3 border-b border-[#242D31] flex items-center justify-between">
          <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">{@title}</p>
          <button phx-click={@close_event} class="font-mono text-[15px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer">
            &times;
          </button>
        </div>
        <div class="p-4">{render_slot(@inner_block)}</div>
        <div class="px-4 py-3 border-t border-[#242D31] flex justify-end gap-2">{render_slot(@actions)}</div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="subscriptions" items={@statusline} right={"#{money(@summary.total_monthly_cents)}/mo"} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-6">
        <div class="rounded-[4px] border border-[#242D31] bg-[#151B1E] px-4 py-3.5 flex items-baseline justify-between">
          <span class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">total monthly cost</span>
          <span class="font-mono text-xl font-semibold text-[#7FB069]">{money(@summary.total_monthly_cents)}</span>
        </div>

        <div class="flex items-center gap-2.5">
          <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">subscriptions</p>
          <span class="h-px flex-1 bg-[#242D31]"></span>
          <button
            phx-click="open_add_modal"
            class="px-3 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            + add subscription
          </button>
        </div>

        <p :if={@summary.groups == []} class="text-[#86948F] text-sm">
          No subscriptions tracked yet. Add one above.
        </p>

        <section :for={group <- @summary.groups}>
          <div class="flex items-baseline gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            {group.label}
            <span class="h-px flex-1 bg-[#242D31]"></span>
            <span class="normal-case tracking-normal text-[13px] text-[#E6ECE9]">{money(group.monthly_subtotal_cents)}/mo</span>
          </div>

          <ul class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
            <.subscription_row
              :for={s <- group.subscriptions}
              subscription={s}
              editing_id={@editing_id}
              edit_form={@edit_form}
              edit_error={@edit_error}
            />
          </ul>
        </section>
      </main>

      <.modal :if={@show_add_modal} title="add subscription" close_event="close_add_modal">
        <form phx-submit="create" id={"add-subscription-form-#{@form_key}"} class="space-y-3">
          <div class="flex flex-col gap-1">
            <label class="font-mono text-[10.5px] text-[#86948F]">name</label>
            <input
              type="text"
              name="subscription[name]"
              placeholder="Name…"
              autocomplete="off"
              required
              class="w-full box-border px-2.5 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
            />
          </div>
          <div class="flex gap-2">
            <div class="flex-1 flex flex-col gap-1">
              <label class="font-mono text-[10.5px] text-[#86948F]">cost</label>
              <input
                type="text"
                inputmode="decimal"
                name="subscription[cost]"
                placeholder="9.99"
                autocomplete="off"
                required
                class="w-full box-border px-2.5 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
              />
            </div>
            <div class="w-[70px] flex flex-col gap-1">
              <label class="font-mono text-[10.5px] text-[#86948F]">every</label>
              <input
                type="number"
                min="1"
                name="subscription[interval_count]"
                value="1"
                class="w-full box-border px-2 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
              />
            </div>
            <div class="w-[100px] flex flex-col gap-1">
              <label class="font-mono text-[10.5px] text-[#86948F]">unit</label>
              <select
                name="subscription[interval_unit]"
                class="w-full box-border px-2 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
              >
                <option value="month">month(s)</option>
                <option value="year">year(s)</option>
              </select>
            </div>
          </div>
          <p :if={@create_error} class="font-mono text-[12px] text-[#C1594A]">{@create_error}</p>
        </form>
        <:actions>
          <button
            phx-click="close_add_modal"
            class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
          >
            cancel
          </button>
          <button
            type="submit"
            form={"add-subscription-form-#{@form_key}"}
            class="px-3 py-[7px] rounded-[4px] border border-[#3C5934] bg-[#151B1E] font-mono text-[11.5px] text-[#7FB069] hover:bg-[#1B2420] cursor-pointer"
          >
            add
          </button>
        </:actions>
      </.modal>
    </div>
    """
  end

  attr :subscription, :map, required: true
  attr :editing_id, :any, required: true
  attr :edit_form, :any, default: nil
  attr :edit_error, :any, default: nil

  defp subscription_row(assigns) do
    editing = assigns.editing_id == assigns.subscription.id
    assigns = assign(assigns, editing: editing)

    ~H"""
    <li :if={!@editing} class="flex items-center gap-3 px-3 py-3">
      <div class="flex-1 min-w-0">
        <span class="text-sm">{@subscription.name}</span>
      </div>
      <div class="text-right shrink-0">
        <p class="text-sm">{money(@subscription.cost_cents)}</p>
        <p class="font-mono text-[10.5px] text-[#86948F]">{money(Subscription.cost_per_month_cents(@subscription))}/mo</p>
      </div>
      <div class="flex flex-col items-center gap-1.5 shrink-0">
        <button
          phx-click="delete"
          phx-value-id={@subscription.id}
          aria-label="Delete subscription"
          class="font-mono text-[#86948F] hover:text-[#C1594A] cursor-pointer"
        >
          ×
        </button>
        <button
          phx-click="start_edit"
          phx-value-id={@subscription.id}
          aria-label="Edit subscription"
          class="font-mono text-[11px] text-[#4A5458] hover:text-[#E6ECE9] cursor-pointer"
        >
          ✎
        </button>
      </div>
    </li>

    <li :if={@editing} class="px-3 py-3">
      <p :if={@edit_error} class="mb-2 font-mono text-[12px] text-[#C1594A]">{@edit_error}</p>

      <form phx-submit="save_edit" class="flex flex-wrap items-end gap-2">
        <div class="flex-1 min-w-[140px]">
          <input
            type="text"
            name="subscription[name]"
            value={@edit_form["name"]}
            required
            class="w-full box-border px-3 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </div>
        <div class="w-[90px]">
          <input
            type="text"
            inputmode="decimal"
            name="subscription[cost]"
            value={@edit_form["cost"]}
            required
            class="w-full box-border px-3 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </div>
        <span class="font-mono text-[12px] text-[#86948F] pb-1.5">every</span>
        <div class="w-[56px]">
          <input
            type="number"
            min="1"
            name="subscription[interval_count]"
            value={@edit_form["interval_count"]}
            class="w-full box-border px-2 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </div>
        <div class="w-[92px]">
          <select
            name="subscription[interval_unit]"
            class="w-full box-border px-2 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
          >
            <option value="month" selected={@edit_form["interval_unit"] == "month"}>month(s)</option>
            <option value="year" selected={@edit_form["interval_unit"] == "year"}>year(s)</option>
          </select>
        </div>
        <button
          type="button"
          phx-click="cancel_edit"
          class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
        >
          Cancel
        </button>
        <button
          type="submit"
          class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
        >
          Save
        </button>
      </form>
    </li>
    """
  end
end
