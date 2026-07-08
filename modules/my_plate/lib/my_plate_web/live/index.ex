defmodule MyPlateWeb.Live.Index do
  @moduledoc """
  My Plate task page (pond-at-night styling per the design mockup):
  add field, priority-grouped list, complete/uncomplete, recurring marker.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("my_plate:tasks")

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("add", %{"title" => title}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, socket}
    else
      case MyPlate.create_task(%{title: title}) do
        {:ok, _task} -> {:noreply, load(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not add task")}
      end
    end
  end

  def handle_event("complete", %{"id" => id}, socket) do
    {:ok, _} = MyPlate.complete_task(id)
    {:noreply, load(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = MyPlate.delete_task(id)
    {:noreply, load(socket)}
  end

  def handle_event("set_priority", %{"id" => id, "priority" => priority}, socket) do
    {:ok, _} = MyPlate.reorder_task(id, priority, 0)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({event, _task}, socket)
      when event in [:task_created, :task_updated, :task_deleted] do
    {:noreply, load(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load(socket) do
    tasks = MyPlate.list_active_tasks()

    assign(socket,
      page_title: "my plate",
      groups:
        for priority <- ["high", "medium", "low"] do
          {priority, Enum.filter(tasks, &(&1.priority == priority))}
        end,
      count: length(tasks)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline
        crumb="my plate"
        items={@statusline}
        right={"#{@count} active"}
      />

      <main class="max-w-[980px] mx-auto px-4 py-6 space-y-7">
        <form phx-submit="add" class="flex gap-2.5">
          <input
            type="text"
            name="title"
            placeholder="Add a task…"
            autocomplete="off"
            class="flex-1 px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
          />
          <button
            type="submit"
            class="px-[18px] py-[9px] rounded-[4px] bg-[#7FB069] text-[#0C1409] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#8fbf7b] cursor-pointer"
          >
            Add
          </button>
        </form>

        <section :for={{priority, tasks} <- @groups} :if={tasks != []}>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            {priority} priority
            <span class="h-px flex-1 bg-[#242D31]"></span>
          </div>
          <ul class="border border-[#242D31] rounded-[4px] bg-[#151B1E] divide-y divide-[#242D31]">
            <li :for={task <- tasks} class="flex items-center gap-3 px-4 py-3">
              <button
                phx-click="complete"
                phx-value-id={task.id}
                aria-label="Complete task"
                class="w-[17px] h-[17px] shrink-0 rounded-full border-[1.5px] border-[#86948F] hover:border-[#7FB069] cursor-pointer"
              >
              </button>
              <span class="flex-1 text-sm min-w-0">{task.title}</span>
              <span :if={task.recurring_task_id} class="font-mono text-[11px] text-[#86948F]">↻</span>
              <span :if={task.due_date} class={[
                "font-mono text-[11.5px] whitespace-nowrap",
                if(Date.compare(task.due_date, MyPlate.today()) != :gt,
                  do: "text-[#E0A458]",
                  else: "text-[#86948F]"
                )
              ]}>
                {task.due_date}
              </span>
              <button
                phx-click="delete"
                phx-value-id={task.id}
                aria-label="Delete task"
                class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
              >
                ×
              </button>
            </li>
          </ul>
        </section>

        <p :if={@count == 0} class="text-[#86948F] text-sm">
          Nothing on your plate. Add a task above.
        </p>
      </main>
    </div>
    """
  end
end
