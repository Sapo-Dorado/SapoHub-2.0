defmodule MyPlateWeb.StatusButton do
  @moduledoc """
  Dashboard button variant "status": icon + name + live active/due counts.
  Rendered inside the standard dashboard slot; the parent re-renders it
  (via the `refresh` assign) whenever my_plate broadcasts task changes.
  """
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(active: MyPlate.count_active_tasks(), due: MyPlate.count_due_today())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contents">
      <span class="w-9 h-9 sm:w-[42px] sm:h-[42px] grid place-items-center rounded-[4px] bg-[#0D1113] border border-[#242D31]">
        <.icon name="hero-clipboard-document-list" class="size-5 text-[#7FB069]" />
      </span>
      <span>
        <span class="block font-mono text-[13.5px] font-semibold tracking-[.02em]">my plate</span>
        <span class="block font-mono text-[11.5px] mt-0.5 whitespace-nowrap">
          <span class="text-[#7FB069]">{@active} active</span>
          <span :if={@due > 0} class="text-[#86948F]"> · </span>
          <span :if={@due > 0} class="text-[#E0A458]">{@due} due</span>
        </span>
      </span>
    </div>
    """
  end

  defp icon(assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end
end
