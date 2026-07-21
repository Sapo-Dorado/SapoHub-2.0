defmodule SapoCoreWeb.Statusline do
  @moduledoc """
  The statusline — SapoHub's signature UI element (see the style guide).

  Two parts:

  * `on_mount {SapoCoreWeb.Statusline, :default}` — LiveView hook that
    loads enabled items, subscribes to their PubSub topics + a 60s refresh
    tick, and keeps the `@statusline` assign current.
  * `<.statusline crumb="settings" />` — the bar itself: brand/home link,
    optional crumb, live items, clock, settings gear.

  `crumb` accepts either a plain string, or a list of `{label, navigate_to}`
  segments (pass `nil` for the current, non-linked segment) to render
  intermediate segments as links back up the hierarchy, e.g.
  `crumb={[{"projects", "/projects"}, {@project.name, nil}]}`.
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

  attr :crumb, :any, default: nil
  attr :items, :list, default: []
  attr :right, :string, default: nil

  def statusline(assigns) do
    assigns = assign(assigns, :crumb_segments, crumb_segments(assigns.crumb))

    ~H"""
    <nav class="flex items-center justify-between h-11 px-4 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs shrink-0">
      <div id="statusline-left" phx-hook="StatuslineFit" class="min-w-0 overflow-hidden whitespace-nowrap">
        <.link navigate="/" class="text-[#7FB069] font-semibold">sapohub</.link>
        <%= for {label, to} <- @crumb_segments do %>
          <span class="text-[#86948F] px-2">/</span>
          <.link :if={to} navigate={to} class="text-[#86948F] hover:text-[#E6ECE9]">{label}</.link>
          <span :if={!to} class="text-[#E6ECE9]">{label}</span>
        <% end %>

        <span
          :for={item <- @items}
          data-statusline-item
          class="pl-3.5 ml-3.5 border-l border-[#242D31] text-[#86948F]"
        >
          <span class={level_class(item.level)}>{item.text}</span>
        </span>
      </div>

      <div class="flex items-center shrink-0 pl-4">
        <span :if={@right} class="text-[#86948F] pr-3.5 mr-3.5 border-r border-[#242D31]">
          {@right}
        </span>
        <span class="text-[#86948F]">{local_clock()}</span>
        <.link
          navigate="/settings"
          aria-label="Settings"
          class="flex items-center justify-center ml-3.5 -mr-4 h-11 w-11 border-l border-[#242D31] text-[#86948F] hover:text-[#7FB069] hover:bg-[#1A2226] transition-colors"
        >
          <.icon name="hero-cog-6-tooth" class="size-[18px]" />
        </.link>
      </div>
    </nav>
    """
  end

  defp crumb_segments(nil), do: []
  defp crumb_segments(crumb) when is_binary(crumb), do: [{crumb, nil}]
  defp crumb_segments(segments) when is_list(segments), do: segments

  defp level_class(:ok), do: "text-[#7FB069]"
  defp level_class(:warn), do: "text-[#E0A458]"
  defp level_class(_), do: "text-[#86948F]"

  # "HH:MM ZONE" in the configured display timezone (services.sapohub.timezone,
  # default UTC). Uses the shifted DateTime's own zone_abbr (e.g. "PST"/"PDT")
  # rather than the raw IANA name, so it reads the way a clock actually would.
  defp local_clock do
    local = DateTime.utc_now() |> SapoCore.Time.local()
    Calendar.strftime(local, "%H:%M") <> " " <> local.zone_abbr
  end
end
