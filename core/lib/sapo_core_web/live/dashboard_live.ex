defmodule SapoCoreWeb.DashboardLive do
  @moduledoc """
  The SapoHub dashboard: a registry-driven grid of module tiles.

  Tiles come from each enabled module's `dashboard_tile/1`. Badges are
  computed asynchronously after mount so a slow module can never block
  page load. Styling is intentionally minimal for now (a dedicated UI
  design pass happens later).
  """
  use SapoCoreWeb, :live_view

  alias SapoCore.Generated.Registry

  @impl true
  def mount(_params, _session, socket) do
    tiles =
      for mod <- Registry.modules(),
          tile = mod.dashboard_tile(Registry.config_for(mod)),
          not is_nil(tile) do
        {mod.id(), tile}
      end

    if connected?(socket) do
      send(self(), :load_badges)
    end

    {:ok, assign(socket, tiles: tiles, badges: %{}), temporary_assigns: []}
  end

  @impl true
  def handle_info(:load_badges, socket) do
    badges =
      for {id, tile} <- socket.assigns.tiles,
          is_function(tile.badge, 0),
          badge = safe_badge(tile.badge),
          not is_nil(badge),
          into: %{} do
        {id, badge}
      end

    {:noreply, assign(socket, badges: badges)}
  end

  defp safe_badge(fun) do
    fun.()
  rescue
    _ -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold">SapoHub</h1>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-4">
          <.module_tile
            :for={{id, tile} <- @tiles}
            id={id}
            tile={tile}
            badge={Map.get(@badges, id)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :atom, required: true
  attr :tile, SapoKit.Tile, required: true
  attr :badge, :string, default: nil

  defp module_tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      id={"tile-#{@id}"}
      class={[
        "card border border-base-300 p-4 hover:border-primary transition-colors relative",
        @tile.style == :wide && "col-span-2",
        @tile.style == :accent && "border-primary bg-primary/5"
      ]}
    >
      <div class="flex items-center gap-3">
        <.icon name={@tile.icon} class="size-6" />
        <span class="font-medium">{@tile.label}</span>
      </div>
      <span
        :if={@badge}
        class="absolute top-2 right-2 badge badge-sm badge-neutral"
      >
        {@badge}
      </span>
    </.link>
    """
  end
end
