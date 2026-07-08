defmodule MyPlateWeb.TaskPreview do
  @moduledoc """
  Dashboard tile variant: a live preview of the most urgent active tasks
  (see `MyPlate.list_tasks_by_urgency/0` — soonest due date first, then
  priority). Declares itself `size: :wide` in `MyPlate.Module` — a short
  list needs real room, which is exactly the bar for reaching for a
  custom tile instead of a one-line statusline item (see
  `SapoKit.DashboardButton`). Rendered inside the dashboard slot; the
  parent re-renders it (via the `refresh` assign) whenever my_plate
  broadcasts task changes.
  """
  use Phoenix.LiveComponent

  @preview_limit 5

  @impl true
  def update(assigns, socket) do
    tasks = MyPlate.list_tasks_by_urgency()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       tasks: Enum.take(tasks, @preview_limit),
       more: max(length(tasks) - @preview_limit, 0)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contents">
      <div class="flex items-center gap-2.5 w-full">
        <span class="w-9 h-9 sm:w-10 sm:h-10 shrink-0 grid place-items-center rounded-[4px] bg-[#0D1113] border border-[#242D31]">
          <.icon name="hero-clipboard-document-list" class="size-5 text-[#7FB069]" />
        </span>
        <span class="font-mono text-[13.5px] font-semibold tracking-[.02em]">my plate</span>
      </div>

      <div class="w-full">
        <p :if={@tasks == []} class="font-mono text-[12px] text-[#86948F]">no active tasks</p>
        <ul :if={@tasks != []} class="flex flex-col gap-[5px]">
          <li :for={task <- @tasks} class="flex items-center gap-2 font-mono text-[12px] leading-none">
            <span class={["size-[6px] rounded-full shrink-0", priority_dot(task.priority)]} />
            <span class="truncate text-[#E6ECE9]">{task.title}</span>
            <span :if={task.recurring_task_id} class="text-[#86948F] shrink-0">↻</span>
            <span :if={task.due_date} class={["ml-auto pl-2 shrink-0", due_color(task.due_date)]}>
              {due_label(task.due_date)}
            </span>
          </li>
          <li :if={@more > 0} class="font-mono text-[11px] text-[#86948F] pt-0.5">
            + {@more} more
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp icon(assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  defp priority_dot("high"), do: "bg-[#C1594A]"
  defp priority_dot("medium"), do: "bg-[#E0A458]"
  defp priority_dot("low"), do: "bg-[#5B7A8C]"
  defp priority_dot(_), do: "bg-[#86948F]"

  defp due_color(date) do
    case Date.diff(date, MyPlate.today()) do
      diff when diff < 0 -> "text-[#C1594A]"
      0 -> "text-[#E0A458]"
      _ -> "text-[#86948F]"
    end
  end

  defp due_label(date) do
    diff = Date.diff(date, MyPlate.today())

    cond do
      diff == 0 -> "today"
      diff == 1 -> "tmrw"
      diff == -1 -> "yesterday"
      diff < -1 -> "#{abs(diff)}d ago"
      diff <= 7 -> date |> Calendar.strftime("%a") |> String.downcase()
      true -> Calendar.strftime(date, "%b %-d")
    end
  end
end
