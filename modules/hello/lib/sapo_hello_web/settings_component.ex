defmodule SapoHelloWeb.SettingsComponent do
  @moduledoc """
  Reference `settings_component()`: a module's own tab on the Settings
  page. Kept deliberately tiny — shows the module's config and a live
  count. Real modules put their knobs here.
  """
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, Map.put(assigns, :count, SapoHello.count_greetings()))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] p-4 space-y-2">
      <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
        Hello (reference module)
      </p>
      <p class="text-sm text-[#E6ECE9]">
        This tab is rendered by the module's <code class="font-mono text-[12.5px]">settings_component()</code>.
        Greetings stored: <span class="font-mono text-[#7FB069]">{@count}</span>.
      </p>
    </div>
    """
  end
end
