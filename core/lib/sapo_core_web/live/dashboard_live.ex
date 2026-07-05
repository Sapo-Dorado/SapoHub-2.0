defmodule SapoCoreWeb.DashboardLive do
  @moduledoc """
  The dashboard: a launcher grid of same-size SLOTS (per the approved
  design). Each slot renders either the module's default button (icon +
  title, first UI route) or a module-provided LiveComponent variant —
  whichever the user picked (`dashboard_button.<id>` pref). Settings is
  NOT a tile; it lives in the statusline gear.
  """
  use SapoCoreWeb, :live_view

  import SapoCoreWeb.Statusline

  alias SapoCore.Generated.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, slots: build_slots())}
  end

  @impl true
  def handle_info({:pref_changed, "dashboard_button." <> _, _}, socket) do
    {:noreply, assign(socket, slots: build_slots())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp build_slots do
    module_slots =
      for mod <- Registry.modules(), path = first_path(mod), not is_nil(path) do
        config = Registry.config_for(mod)
        variant = SapoCore.Prefs.get("dashboard_button.#{mod.id()}", "default")

        component =
          Enum.find_value(mod.dashboard_buttons(config), fn button ->
            if button.id == variant, do: button.component
          end)

        %{
          id: mod.id(),
          title: String.downcase(mod.title()),
          icon: mod.icon(),
          path: path,
          component: component
        }
      end

    core_slots = [
      %{
        id: :assistant,
        title: "assistant",
        icon: "hero-command-line",
        path: "/assistant",
        component: nil
      }
    ]

    module_slots ++ core_slots
  end

  defp first_path(mod) do
    case mod.ui_routes() do
      [%{path: path} | _] -> path
      [] -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <.statusline items={@statusline} />

      <main class="max-w-[1080px] mx-auto px-4 py-9">
        <div class="flex items-center gap-2.5 mb-3.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
          Utilities <span class="h-px flex-1 bg-[#242D31]"></span>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-[repeat(auto-fill,minmax(250px,1fr))] gap-3 sm:gap-3.5">
          <.link
            :for={slot <- @slots}
            navigate={slot.path}
            id={"slot-#{slot.id}"}
            class="flex flex-col items-start justify-between gap-2.5 min-h-[110px] sm:min-h-[128px] p-[14px] sm:p-[18px] rounded-[4px] bg-[#151B1E] border border-[#242D31] hover:border-[#3C5934] hover:bg-[#1A2226] transition-colors"
          >
            <%= if slot.component do %>
              <.live_component
                module={slot.component}
                id={"slot-content-#{slot.id}"}
                module_id={slot.id}
                refresh={:erlang.phash2(@statusline)}
              />
            <% else %>
              <span class="w-9 h-9 sm:w-[42px] sm:h-[42px] grid place-items-center rounded-[4px] bg-[#0D1113] border border-[#242D31]">
                <.icon name={slot.icon} class="size-5 text-[#7FB069]" />
              </span>
              <span class="font-mono text-[13.5px] font-semibold tracking-[.02em]">
                {slot.title}
              </span>
            <% end %>
          </.link>
        </div>
      </main>
    </div>
    """
  end
end
