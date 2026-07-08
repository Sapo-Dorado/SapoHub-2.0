defmodule SapoCoreWeb.DashboardLive do
  @moduledoc """
  The dashboard: a launcher grid of SLOTS on a fixed 3-column track (sm+;
  2 columns on mobile), in the order given by `SapoCore.Dashboard`. Each
  slot renders either the standard tile (icon + title, first UI route,
  `:standard` = 1 column) or one of the module's `dashboard_buttons/1`
  options (see `SapoKit.DashboardButton`) — whichever the user picked
  (`dashboard_button.<id>` pref, `"default"` unless changed in Settings).
  Each option sets its own `:size`, independent of how many options a
  module offers: `:wide` takes 2 of the 3 columns (the grid's normal
  auto-placement packs a standard 1-column tile in beside it);
  `:extra_wide` takes all 3 (its row is its alone). Settings is NOT a
  tile (it lives in the statusline gear), and neither is the assistant
  (a floating button in the root layout, on every page — see
  `SapoCore.Dashboard`).
  """
  use SapoCoreWeb, :live_view

  import SapoCoreWeb.Statusline

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, slots: SapoCore.Dashboard.ordered_slots())}
  end

  @impl true
  def handle_info({:pref_changed, "dashboard_button." <> _, _}, socket) do
    {:noreply, assign(socket, slots: SapoCore.Dashboard.ordered_slots())}
  end

  def handle_info({:pref_changed, "dashboard_order", _}, socket) do
    {:noreply, assign(socket, slots: SapoCore.Dashboard.ordered_slots())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <.statusline items={@statusline} />

      <main class="max-w-[1080px] mx-auto px-4 py-9">
        <div class="flex items-center gap-2.5 mb-3.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
          Utilities <span class="h-px flex-1 bg-[#242D31]"></span>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 sm:gap-3.5">
          <.tile :for={slot <- @slots} slot={slot} statusline={@statusline} />
        </div>
      </main>
    </div>
    """
  end

  attr :slot, :map, required: true
  attr :statusline, :list, required: true

  defp tile(assigns) do
    ~H"""
    <.link
      navigate={@slot.path}
      id={"slot-#{@slot.id}"}
      class={[
        "flex flex-col items-start justify-between gap-2.5 min-h-[110px] sm:min-h-[128px] p-[14px] sm:p-[18px] rounded-[4px] bg-[#151B1E] border border-[#242D31] hover:border-[#3C5934] hover:bg-[#1A2226] transition-colors",
        size_class(@slot.size)
      ]}
    >
      <%= if @slot.component do %>
        <.live_component
          module={@slot.component}
          id={"slot-content-#{@slot.id}"}
          module_id={@slot.id}
          size={@slot.size}
          refresh={:erlang.phash2(@statusline)}
        />
      <% else %>
        <span class="w-9 h-9 sm:w-[42px] sm:h-[42px] grid place-items-center rounded-[4px] bg-[#0D1113] border border-[#242D31]">
          <.icon name={@slot.icon} class="size-5 text-[#7FB069]" />
        </span>
        <span class="font-mono text-[13.5px] font-semibold tracking-[.02em]">
          {@slot.title}
        </span>
      <% end %>
    </.link>
    """
  end

  # Mobile is a 2-column grid, sm+ is 3 columns — `:wide` (2 cols) happens
  # to fit both without a breakpoint prefix. `:extra_wide` (3 cols) needs
  # different spans per breakpoint; `max-sm:`/`sm:` are used (rather than
  # a bare `col-span-2 sm:col-span-3`) so the two rules apply over
  # mutually-exclusive ranges instead of both matching at sm+ and leaving
  # the result up to cascade order.
  defp size_class(:wide), do: "col-span-2"
  defp size_class(:extra_wide), do: "max-sm:col-span-2 sm:col-span-3"
  defp size_class(_), do: nil
end
