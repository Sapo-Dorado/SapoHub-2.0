defmodule SapoCoreWeb.Statusline do
  @moduledoc """
  The statusline — SapoHub's signature UI element (see the style guide).

  Two parts:

  * `on_mount {SapoCoreWeb.Statusline, :default}` — LiveView hook that
    loads enabled items, subscribes to their PubSub topics + a 60s refresh
    tick, and keeps the `@statusline` assign current.
  * `<.statusline crumb="settings" />` — the bar itself: brand/home link,
    optional crumb, live items, clock, settings gear.
  """

  use Phoenix.Component

  import Phoenix.LiveView
  import SapoCoreWeb.CoreComponents, only: [icon: 1]

  alias SapoCore.Statusline, as: Items

  @refresh_ms 60_000

  # ── on_mount hook ──────────────────────────────────────────────────────────

  def on_mount(:default, _params, _session, socket) do
    socket =
      if connected?(socket) do
        for topic <- Items.topics(), do: SapoKit.PubSub.subscribe(topic)
        SapoKit.PubSub.subscribe("prefs")
        Process.send_after(self(), :statusline_refresh, @refresh_ms)
        socket
      else
        socket
      end

    socket =
      socket
      |> Phoenix.Component.assign(:statusline, Items.evaluate())
      |> attach_hook(:statusline, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_info(:statusline_refresh, socket) do
    Process.send_after(self(), :statusline_refresh, @refresh_ms)
    {:halt, refresh(socket)}
  end

  defp handle_info({:pref_changed, "statusline." <> _, _}, socket) do
    {:halt, refresh(socket)}
  end

  defp handle_info({:pref_changed, "statusline_order", _}, socket) do
    {:halt, refresh(socket)}
  end

  # Any broadcast on a subscribed item topic re-evaluates the bar, then the
  # message continues to the LiveView's own handle_info.
  defp handle_info(_msg, socket) do
    {:cont, refresh(socket)}
  end

  defp refresh(socket), do: Phoenix.Component.assign(socket, :statusline, Items.evaluate())

  # ── Component ──────────────────────────────────────────────────────────────

  attr :crumb, :string, default: nil
  attr :items, :list, default: []
  attr :right, :string, default: nil

  def statusline(assigns) do
    ~H"""
    <nav class="flex items-center h-11 px-4 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs overflow-x-auto whitespace-nowrap shrink-0 [scrollbar-width:none]">
      <.link navigate="/" class="text-[#7FB069] font-semibold">sapohub</.link>
      <span :if={@crumb} class="text-[#86948F] px-2">/</span>
      <span :if={@crumb} class="text-[#E6ECE9]">{@crumb}</span>

      <span
        :for={item <- @items}
        class="pl-3.5 ml-3.5 border-l border-[#242D31] text-[#86948F]"
      >
        <span class={level_class(item.level)}>{item.text}</span>
      </span>

      <span class="flex-1"></span>
      <span :if={@right} class="text-[#86948F] pr-3.5 mr-3.5 border-r border-[#242D31]">
        {@right}
      </span>
      <span class="text-[#86948F]">{Calendar.strftime(DateTime.utc_now(), "%H:%M")} UTC</span>
      <.link
        navigate="/settings"
        aria-label="Settings"
        class="flex items-center justify-center ml-3.5 -mr-4 h-11 w-11 border-l border-[#242D31] text-[#86948F] hover:text-[#7FB069] hover:bg-[#1A2226] transition-colors"
      >
        <.icon name="hero-cog-6-tooth" class="size-[18px]" />
      </.link>
    </nav>
    """
  end

  defp level_class(:ok), do: "text-[#7FB069]"
  defp level_class(:warn), do: "text-[#E0A458]"
  defp level_class(_), do: "text-[#86948F]"
end
