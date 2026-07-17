defmodule MyPlateWeb.Live.Index do
  @moduledoc """
  My Plate task page: priority-grouped, color-coded, drag-reorderable task
  list; a per-priority-section creation modal (title + due date, priority
  implied by which section's "+" was clicked); and a recurring-tasks
  management modal (create/edit/delete/toggle-active). Draggability is
  provided by the module-contributed `TaskSortable` JS hook (see
  `assets/hooks.js`) — dropping a task pushes `"reorder"` with the same
  `{task_id, new_priority, new_position}` shape `MyPlate.reorder_task/3`
  already expects.
  """
  use SapoKit.Web, :live_view

  alias MyPlate.Board
  alias MyPlate.RecurringTask

  @priorities ["high", "medium", "low"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("my_plate:tasks")

    {:ok,
     assign(socket,
       adding_to: nil,
       recurring_open: false,
       recurring_editing: nil,
       recurring_tasks: [],
       recurring_form: nil,
       board_menu_open: false,
       boards_modal_open: false,
       board_editing: nil,
       board_form: nil,
       confirm_delete_board: nil,
       confirm_delete_task: nil,
       undo_stack: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case resolve_scope(params["board_id"]) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(scope: scope, boards: MyPlate.list_boards(), board_menu_open: false)
         |> load()}

      :not_found ->
        {:noreply,
         socket
         |> put_flash(:error, "board not found")
         |> push_navigate(to: "/my-plate")}
    end
  end

  defp resolve_scope(nil), do: {:ok, :global}

  defp resolve_scope(board_id) do
    case MyPlate.get_board(board_id) do
      nil -> :not_found
      board -> {:ok, {:board, board}}
    end
  end

  # ── Tasks ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("show_add_form", %{"priority" => priority}, socket) do
    {:noreply, assign(socket, adding_to: priority)}
  end

  def handle_event("close_add_form", _, socket) do
    {:noreply, assign(socket, adding_to: nil)}
  end

  def handle_event("create_task", %{"task" => params}, socket) do
    params =
      params
      |> Map.put_new("due_date", nil)
      |> Map.put_new("board_id", scope_board_id(socket.assigns.scope))

    case MyPlate.create_task(params) do
      {:ok, _task} -> {:noreply, socket |> assign(adding_to: nil) |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not add task")}
    end
  end

  def handle_event("complete", %{"id" => id}, socket) do
    task = MyPlate.get_task!(id)
    {:ok, _} = MyPlate.complete_task(task)
    {:noreply, socket |> push_undo(task) |> load()}
  end

  def handle_event("confirm_delete_task", %{"id" => id}, socket) do
    task = MyPlate.get_task!(id)
    {:noreply, assign(socket, confirm_delete_task: %{id: task.id, title: task.title})}
  end

  def handle_event("cancel_delete_task", _, socket) do
    {:noreply, assign(socket, confirm_delete_task: nil)}
  end

  def handle_event("delete_task", %{"id" => id}, socket) do
    {:ok, _} = MyPlate.delete_task(id)
    {:noreply, socket |> assign(confirm_delete_task: nil) |> load()}
  end

  def handle_event("undo", _, socket) do
    case socket.assigns.undo_stack do
      [] ->
        {:noreply, socket}

      [task | rest] ->
        {:ok, _} = MyPlate.uncomplete_task(MyPlate.get_task!(task.id))
        {:noreply, socket |> assign(undo_stack: rest) |> load()}
    end
  end

  def handle_event(
        "reorder",
        %{"task_id" => id, "new_priority" => priority, "new_position" => position},
        socket
      ) do
    {:ok, _} = MyPlate.reorder_task(id, priority, position)
    {:noreply, load(socket)}
  end

  def handle_event("save_due_date", %{"task_id" => id, "due_date" => due_date}, socket) do
    due_date = if due_date == "", do: nil, else: due_date
    {:ok, _} = MyPlate.update_task(MyPlate.get_task!(id), %{"due_date" => due_date})
    {:noreply, load(socket)}
  end

  # ── Board scope ──────────────────────────────────────────────────────────

  def handle_event("toggle_board_menu", _, socket) do
    {:noreply, assign(socket, board_menu_open: !socket.assigns.board_menu_open)}
  end

  def handle_event("close_board_menu", _, socket) do
    {:noreply, assign(socket, board_menu_open: false)}
  end

  def handle_event("open_boards_modal", _, socket) do
    {:noreply, assign(socket, boards_modal_open: true, board_menu_open: false)}
  end

  def handle_event("close_boards_modal", _, socket) do
    {:noreply,
     assign(socket, boards_modal_open: false, board_editing: nil, board_form: nil, confirm_delete_board: nil)}
  end

  def handle_event("new_board", _, socket) do
    {:noreply, assign(socket, board_editing: :new, board_form: %{})}
  end

  def handle_event("edit_board", %{"id" => id}, socket) do
    board = MyPlate.get_board!(id)
    {:noreply, assign(socket, board_editing: id, board_form: %{"name" => board.name})}
  end

  def handle_event("cancel_board_form", _, socket) do
    {:noreply, assign(socket, board_editing: nil, board_form: nil)}
  end

  def handle_event("update_board_form", %{"board" => params}, socket) do
    {:noreply, assign(socket, board_form: params)}
  end

  def handle_event("save_board", %{"board" => params}, socket) do
    result =
      case socket.assigns.board_editing do
        :new -> MyPlate.create_board(params)
        id -> MyPlate.update_board(MyPlate.get_board!(id), params)
      end

    case result do
      {:ok, _board} ->
        {:noreply,
         assign(socket, board_editing: nil, board_form: nil, boards: MyPlate.list_boards())}

      {:error, changeset} ->
        {:noreply, assign(socket, board_form: raw_params_with_errors(params, changeset))}
    end
  end

  def handle_event("confirm_delete_board", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirm_delete_board: id)}
  end

  def handle_event("cancel_delete_board", _, socket) do
    {:noreply, assign(socket, confirm_delete_board: nil)}
  end

  def handle_event("delete_board", %{"id" => id}, socket) do
    {:ok, _} = MyPlate.delete_board(id)
    deleted_current? = match?({:board, %Board{id: ^id}}, socket.assigns.scope)

    socket =
      assign(socket,
        boards: MyPlate.list_boards(),
        confirm_delete_board: nil
      )

    if deleted_current? do
      {:noreply, push_navigate(socket, to: "/my-plate")}
    else
      {:noreply, load(socket)}
    end
  end

  # ── Recurring tasks ─────────────────────────────────────────────────────

  def handle_event("show_recurring", _, socket) do
    {:noreply, assign(socket, recurring_open: true, recurring_tasks: MyPlate.list_all_recurring_tasks())}
  end

  def handle_event("close_recurring", _, socket) do
    {:noreply, assign(socket, recurring_open: false, recurring_editing: nil)}
  end

  def handle_event("new_recurring", _, socket) do
    {:noreply, assign(socket, recurring_editing: :new, recurring_form: %{})}
  end

  def handle_event("edit_recurring", %{"id" => id}, socket) do
    rt = MyPlate.get_recurring_task!(id)
    {:noreply, assign(socket, recurring_editing: id, recurring_form: recurring_form_data(rt))}
  end

  def handle_event("cancel_recurring_form", _, socket) do
    {:noreply, assign(socket, recurring_editing: nil, recurring_form: nil)}
  end

  def handle_event("update_recurring_form", %{"recurring_task" => params}, socket) do
    {:noreply, assign(socket, recurring_form: params)}
  end

  def handle_event("save_recurring", %{"recurring_task" => params}, socket) do
    result =
      case socket.assigns.recurring_editing do
        :new -> MyPlate.create_recurring_task(params)
        id -> MyPlate.update_recurring_task(MyPlate.get_recurring_task!(id), params)
      end

    case result do
      {:ok, _rt} ->
        {:noreply,
         assign(socket,
           recurring_editing: nil,
           recurring_form: nil,
           recurring_tasks: MyPlate.list_all_recurring_tasks()
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, recurring_form: raw_params_with_errors(params, changeset))}
    end
  end

  def handle_event("delete_recurring", %{"id" => id}, socket) do
    :ok = id |> MyPlate.get_recurring_task!() |> MyPlate.delete_recurring_task() |> ok_or_raise()
    {:noreply, assign(socket, recurring_tasks: MyPlate.list_all_recurring_tasks())}
  end

  def handle_event("toggle_recurring_active", %{"id" => id}, socket) do
    rt = MyPlate.get_recurring_task!(id)
    {:ok, _} = MyPlate.update_recurring_task(rt, %{"active" => !rt.active})
    {:noreply, assign(socket, recurring_tasks: MyPlate.list_all_recurring_tasks())}
  end

  @impl true
  def handle_info({event, _task}, socket)
      when event in [:task_created, :task_updated, :task_deleted] do
    {:noreply, load(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load(socket) do
    tasks = MyPlate.list_active_tasks(socket.assigns.scope)

    assign(socket,
      page_title: page_title(socket.assigns.scope),
      groups: for(priority <- @priorities, do: {priority, Enum.filter(tasks, &(&1.priority == priority))}),
      count: length(tasks)
    )
  end

  defp page_title(:global), do: "my plate"
  defp page_title({:board, %Board{name: name}}), do: "my plate — #{name}"

  defp scope_label(:global), do: "global"
  defp scope_label({:board, %Board{name: name}}), do: name

  defp scope_board_id(:global), do: nil
  defp scope_board_id({:board, %Board{id: id}}), do: id

  defp recurring_form_data(%RecurringTask{} = rt) do
    %{
      "title" => rt.title,
      "priority" => rt.priority,
      "recurrence" => rt.recurrence,
      "day_of_week" => rt.day_of_week && to_string(rt.day_of_week),
      "day_of_month" => rt.day_of_month && to_string(rt.day_of_month)
    }
  end

  defp raw_params_with_errors(params, _changeset), do: params

  defp ok_or_raise({:ok, _}), do: :ok
  defp ok_or_raise({:error, reason}), do: raise("delete_recurring_task failed: #{inspect(reason)}")

  defp push_undo(socket, task) do
    stack = [task | socket.assigns.undo_stack] |> Enum.take(5)
    assign(socket, undo_stack: stack)
  end

  defp undo_label(task), do: "completed \"#{task.title}\""

  # ── Priority styling (shared across the task list and both modals) ──────

  defp priority_dot("high"), do: "bg-[#C1594A]"
  defp priority_dot("medium"), do: "bg-[#E0A458]"
  defp priority_dot("low"), do: "bg-[#5B7A8C]"

  defp priority_text("high"), do: "text-[#C1594A]"
  defp priority_text("medium"), do: "text-[#E0A458]"
  defp priority_text("low"), do: "text-[#5B7A8C]"

  defp priority_border("high"), do: "border-[#C1594A]"
  defp priority_border("medium"), do: "border-[#E0A458]"
  defp priority_border("low"), do: "border-[#5B7A8C]"

  defp priority_button("high"), do: "bg-[#C1594A] hover:bg-[#cc6a5b] text-[#1A0D0A]"
  defp priority_button("medium"), do: "bg-[#E0A458] hover:bg-[#e8b370] text-[#1A1206]"
  defp priority_button("low"), do: "bg-[#5B7A8C] hover:bg-[#6c8a9c] text-[#0A1216]"

  defp due_date_class(due_date) do
    if Date.compare(due_date, MyPlate.today()) != :gt,
      do: "text-[#E0A458]",
      else: "text-[#86948F] hover:text-[#E6ECE9]"
  end

  defp board_name(boards, board_id) do
    case Enum.find(boards, &(&1.id == board_id)) do
      nil -> nil
      board -> board.name
    end
  end

  defp weekday_name(1), do: "Monday"
  defp weekday_name(2), do: "Tuesday"
  defp weekday_name(3), do: "Wednesday"
  defp weekday_name(4), do: "Thursday"
  defp weekday_name(5), do: "Friday"
  defp weekday_name(6), do: "Saturday"
  defp weekday_name(7), do: "Sunday"

  defp recurrence_summary(%RecurringTask{recurrence: "daily"}), do: "daily"

  defp recurrence_summary(%RecurringTask{recurrence: "weekly", day_of_week: dow}) when is_integer(dow),
    do: "weekly · #{weekday_name(dow)}"

  defp recurrence_summary(%RecurringTask{recurrence: "monthly", day_of_month: dom}) when is_integer(dom),
    do: "monthly · day #{dom}"

  defp recurrence_summary(_), do: "—"

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      /*
        SortableJS's ghostClass ("task-ghost") marks the placeholder row
        showing where the dragged item will land inside the TARGET list —
        distinct from .task-fallback below, which is the separate clone
        that follows the cursor. A translucent "lifted" look reads fine
        here: the thing it used to collide with (an empty section's
        "Nothing here." text) is now hidden outright for the duration of
        any drag — see the `[.my-plate-dragging_&]` variant on that <p>,
        toggled by TaskSortable's onStart/onEnd (hooks.js) — so there's
        nothing left underneath for a semi-transparent ghost to blend
        into.
      */
      .task-ghost {
        opacity: 0.5 !important;
        background: #151B1E !important;
        border: 1px solid #242D31 !important;
      }
      /*
        The floating clone that follows the cursor during a drag (only a
        real, stylable DOM element now that hooks.js sets forceFallback —
        see that file's comment for why). Translucent like the ghost
        above, for the same reason: whatever's underneath is already
        hidden while a drag is active, so this can look like a "lifted"
        card instead of a fully solid duplicate.

        `fallbackOnBody: true` (hooks.js) appends this clone as a direct
        child of <body>, outside the page's own wrapper div — which is
        where `text-[#E6ECE9]` actually lives; every row's own text relies
        on inheriting it rather than declaring its own color. Escaping
        that wrapper meant the clone fell back to Tailwind's preflight
        default (near-black), rendering the title as good as invisible
        against the dark card background. Set it explicitly here instead
        of relying on inheritance.
      */
      .task-fallback,
      .task-fallback * {
        color: #E6ECE9 !important;
      }
      .task-fallback {
        background: #151B1E !important;
        border: 1px solid #3C5934 !important;
        border-radius: 4px;
        opacity: 0.85 !important;
        box-shadow: none !important;
      }
      /*
        Hides "Nothing here." for the duration of any drag (TaskSortable
        in hooks.js toggles my-plate-dragging on <body> via onStart/onEnd).
        Written as a plain flat selector rather than Tailwind's
        `[.my-plate-dragging_&]:opacity-0` arbitrary-variant — that
        compiles to native CSS nesting (`.my-plate-dragging & { ... }`),
        which only landed in Safari 16.5 (May 2023); on an iOS device
        below that, or hitting any nesting-parser quirk, the whole rule
        gets silently dropped and the text just never fades — which is
        exactly the "still visible" report on iOS specifically, while
        desktop Chrome (fully supports nesting) showed no problem in
        testing. A plain descendant selector has no such floor.
      */
      .my-plate-dragging .my-plate-empty-text {
        opacity: 0 !important;
      }
    </style>
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline
        crumb="my plate"
        items={@statusline}
        right={"#{@count} active"}
      />

      <main class="max-w-[980px] mx-auto px-4 py-6 space-y-7">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <h1 class="font-mono text-[13.5px] font-semibold text-[#E6ECE9]">my plate</h1>
            <div class="relative">
              <button
                phx-click="toggle_board_menu"
                class="flex items-center gap-1 px-2.5 py-[5px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
              >
                <span class="text-[9px] leading-none">▾</span> {scope_label(@scope)}
              </button>

              <div
                :if={@board_menu_open}
                phx-click-away="close_board_menu"
                class="absolute left-0 top-[calc(100%+4px)] z-40 w-[200px] rounded-[4px] bg-[#151B1E] border border-[#242D31] py-1"
              >
                <.link
                  patch="/my-plate"
                  class={[
                    "flex items-center gap-1.5 px-3 py-[7px] font-mono text-[12px] hover:bg-[#0D1113]",
                    if(@scope == :global, do: "text-[#E6ECE9]", else: "text-[#86948F]")
                  ]}
                >
                  <span class="w-[12px] shrink-0">{if @scope == :global, do: "✓"}</span> global
                </.link>

                <div :if={@boards != []} class="h-px my-1 bg-[#242D31]"></div>

                <.link
                  :for={board <- @boards}
                  patch={"/my-plate/#{board.id}"}
                  class={[
                    "flex items-center gap-1.5 px-3 py-[7px] font-mono text-[12px] truncate hover:bg-[#0D1113]",
                    if(match?({:board, %Board{id: id}} when id == board.id, @scope),
                      do: "text-[#E6ECE9]",
                      else: "text-[#86948F]"
                    )
                  ]}
                >
                  <span class="w-[12px] shrink-0">
                    {if match?({:board, %Board{id: id}} when id == board.id, @scope), do: "✓"}
                  </span>
                  {board.name}
                </.link>

                <div class="h-px my-1 bg-[#242D31]"></div>

                <button
                  phx-click="open_boards_modal"
                  class="w-full text-left px-3 py-[7px] font-mono text-[12px] text-[#86948F] hover:text-[#7FB069] hover:bg-[#0D1113] cursor-pointer"
                >
                  + new board
                </button>
                <button
                  phx-click="open_boards_modal"
                  class="w-full text-left px-3 py-[7px] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:bg-[#0D1113] cursor-pointer"
                >
                  manage boards
                </button>
              </div>
            </div>
          </div>
          <button
            phx-click="show_recurring"
            class="flex items-center gap-1.5 px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            <span class="text-sm leading-none">↻</span> recurring
          </button>
        </div>

        <section :for={{priority, tasks} <- @groups}>
          <div class="flex items-center gap-2.5 mb-3 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            <span class={["size-1.5 rounded-full", priority_dot(priority)]}></span>
            {priority} priority
            <span class="h-px flex-1 bg-[#242D31]"></span>
            <button
              phx-click="show_add_form"
              phx-value-priority={priority}
              aria-label={"Add #{priority} priority task"}
              class={[
                "flex items-center justify-center w-[20px] h-[20px] rounded-[3px] border font-mono text-[13px] leading-none cursor-pointer transition-colors",
                "border-[#242D31] text-[#86948F] hover:text-[#E6ECE9]",
                "hover:" <> priority_border(priority)
              ]}
            >
              +
            </button>
          </div>

          <!--
            The sortable container is ALWAYS mounted, even with zero tasks —
            never swapped out for a plain empty-state element. An empty
            priority section still needs a live SortableJS drop target, or
            cross-category drags into it have nowhere to land (and a
            just-emptied section would tear down its Sortable instance
            mid-interaction). The "Nothing here" copy is a separate,
            pointer-events-none sibling overlaid on top instead of a
            replacement — same structural pattern v1 uses.
          -->
          <div class="relative">
            <ul
              id={"task-list-#{priority}"}
              phx-hook="TaskSortable"
              data-group={priority}
              class={[
                "min-h-[44px] rounded-[4px] divide-y divide-[#242D31]",
                if(tasks == [],
                  do: "bg-[#12171A]",
                  else: "border border-[#242D31] bg-[#151B1E]"
                )
              ]}
            >
              <li
                :for={task <- tasks}
                id={"task-#{task.id}"}
                data-id={task.id}
                class="group flex items-center gap-3 px-3 py-3"
              >
                <span class="drag-handle shrink-0 cursor-grab active:cursor-grabbing text-[#3C5934] hover:text-[#86948F] font-mono text-[13px] leading-none select-none px-0.5">
                  ⠿
                </span>
                <button
                  phx-click="complete"
                  phx-value-id={task.id}
                  aria-label="Complete task"
                  class={[
                    "w-[17px] h-[17px] shrink-0 rounded-full border-[1.5px] hover:border-[#7FB069] cursor-pointer",
                    priority_border(priority)
                  ]}
                >
                </button>
                <% board_name = @scope == :global && task.board_id && board_name(@boards, task.board_id) %>
                <div class="flex-1 min-w-0 flex flex-col">
                  <span class="text-sm truncate">{task.title}</span>
                  <span :if={board_name} class="font-mono text-[10.5px] text-[#86948F] truncate">
                    {board_name}
                  </span>
                </div>
                <span :if={task.recurring_task_id} class="font-mono text-[11px] text-[#86948F]" title="Recurring task">↻</span>
                <form phx-change="save_due_date" class="shrink-0">
                  <input type="hidden" name="task_id" value={task.id} />
                  <input
                    type="date"
                    name="due_date"
                    id={"due-date-input-#{task.id}"}
                    value={task.due_date}
                    class="sr-only"
                  />
                  <button
                    type="button"
                    id={"due-date-btn-#{task.id}"}
                    phx-hook="DueDatePicker"
                    data-input-id={"due-date-input-#{task.id}"}
                    class={[
                      "font-mono text-[11.5px] whitespace-nowrap cursor-pointer transition-opacity",
                      if(task.due_date,
                        do: due_date_class(task.due_date),
                        else: "text-[#86948F] opacity-40 group-hover:opacity-100 hover:text-[#E6ECE9]"
                      )
                    ]}
                  >
                    {task.due_date || "set due date"}
                  </button>
                </form>
                <button
                  phx-click="confirm_delete_task"
                  phx-value-id={task.id}
                  aria-label="Delete task"
                  class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
                >
                  ×
                </button>
              </li>
            </ul>
            <p
              :if={tasks == []}
              class="my-plate-empty-text absolute inset-0 flex items-center px-3 font-mono text-[12px] text-[#86948F] pointer-events-none"
            >
              Nothing here.
            </p>
          </div>
        </section>

        <p :if={@count == 0} class="text-[#86948F] text-sm">
          Nothing on your plate. Add a task with the + on any priority above.
        </p>

        <button
          :if={@undo_stack != []}
          phx-click="undo"
          class="block mx-auto px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
        >
          undo — {undo_label(hd(@undo_stack))}
        </button>
      </main>

      <.add_task_modal :if={@adding_to} priority={@adding_to} />
      <.delete_task_modal :if={@confirm_delete_task} task={@confirm_delete_task} />
      <.recurring_modal
        :if={@recurring_open}
        editing={@recurring_editing}
        form={@recurring_form}
        recurring_tasks={@recurring_tasks}
      />
      <.boards_modal
        :if={@boards_modal_open}
        editing={@board_editing}
        form={@board_form}
        boards={@boards}
        confirm_delete={@confirm_delete_board}
      />
    </div>
    """
  end

  # ── Task creation modal ──────────────────────────────────────────────────

  attr :priority, :string, required: true

  defp add_task_modal(assigns) do
    ~H"""
    <div
      id="add-task-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      phx-window-keydown="close_add_form"
      phx-key="escape"
    >
      <div class="absolute inset-0" phx-click="close_add_form"></div>
      <div class={[
        "relative w-full max-w-[400px] rounded-[4px] bg-[#151B1E] border border-[#242D31] border-l-[3px] overflow-hidden",
        priority_border(@priority)
      ]}>
        <div class="px-4 pt-4 pb-3 border-b border-[#242D31]">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            add — <span class={priority_text(@priority)}>{@priority} priority</span>
          </div>
        </div>

        <form phx-submit="create_task" class="px-4 py-4 space-y-3">
          <input type="hidden" name="task[priority]" value={@priority} />
          <div class="min-w-0">
            <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">title</label>
            <input
              type="text"
              name="task[title]"
              id="add-task-title"
              phx-hook="AutoSelect"
              placeholder="Task title…"
              autocomplete="off"
              required
              class="w-full min-w-0 box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
            />
          </div>
          <div class="min-w-0">
            <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">due date (optional)</label>
            <!--
              Recurring overflow bug (also present in v1): a native
              <input type="date"> has an internal mm/dd/yyyy + calendar-icon
              layout with its own minimum content width, which some
              browsers will render past an author-specified `width` rather
              than shrink — even though the box itself is `border-box`.
              The actual fix lives in app.css (Chrome/Safari build this
              control from an internal shadow-DOM tree with its own UA
              min-width — `min-w-0` here on the input's own box can't
              reach that; the app.css rule zeroes the shadow parts'
              min-width directly). `min-w-0` here is still worth keeping:
              it's what lets this input's box actually honor `w-full`
              rather than fall back to the UA's implicit `min-width: auto`.
              `overflow-hidden` on the modal card (above) stays too, as a
              backstop for any browser/locale combination the app.css rule
              doesn't cover — clips at the card's rounded border instead of
              spilling past it. The native calendar *popup* itself is
              unaffected either way — it's painted by the browser's UI
              layer, not page layout.
            -->
            <input
              type="date"
              name="task[due_date]"
              class="w-full min-w-0 box-border pl-3 pr-4 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none [color-scheme:dark] [&::-webkit-calendar-picker-indicator]:mr-0"
            />
          </div>

          <div class="flex items-center justify-end gap-2 pt-2">
            <button
              type="button"
              phx-click="close_add_form"
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              class={[
                "px-4 py-[7px] rounded-[4px] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer",
                priority_button(@priority)
              ]}
            >
              Add task
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ── Delete task confirmation modal ───────────────────────────────────────

  attr :task, :map, required: true

  defp delete_task_modal(assigns) do
    ~H"""
    <div
      id="delete-task-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      phx-window-keydown="cancel_delete_task"
      phx-key="escape"
    >
      <div class="absolute inset-0" phx-click="cancel_delete_task"></div>
      <div class="relative w-full max-w-[400px] rounded-[4px] bg-[#151B1E] border border-[#242D31] border-l-[3px] border-l-[#C1594A] overflow-hidden">
        <div class="px-4 pt-4 pb-3 border-b border-[#242D31]">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            delete task
          </div>
        </div>

        <div class="px-4 py-4 space-y-4">
          <p class="text-sm text-[#E6ECE9]">
            Delete "<span class="font-semibold">{@task.title}</span>"? This can't be undone.
          </p>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_delete_task"
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="delete_task"
              phx-value-id={@task.id}
              class="px-4 py-[7px] rounded-[4px] bg-[#C1594A] hover:bg-[#cc6a5b] text-[#1A0D0A] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Recurring tasks modal ─────────────────────────────────────────────────

  attr :editing, :any, required: true
  attr :form, :any, required: true
  attr :recurring_tasks, :list, required: true

  defp recurring_modal(assigns) do
    ~H"""
    <div
      id="recurring-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      phx-window-keydown="close_recurring"
      phx-key="escape"
    >
      <div class="absolute inset-0" phx-click="close_recurring"></div>
      <div class="relative w-full max-w-[480px] max-h-[80vh] overflow-y-auto rounded-[4px] bg-[#151B1E] border border-[#242D31]">
        <div class="flex items-center justify-between px-4 pt-4 pb-3 border-b border-[#242D31]">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            recurring tasks
          </div>
          <button phx-click="close_recurring" class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer">×</button>
        </div>

        <div class="p-4">
          <.recurring_form :if={@editing} editing={@editing} form={@form} />

          <div :if={!@editing} class="space-y-3">
            <button
              phx-click="new_recurring"
              class="w-full px-3 py-[9px] rounded-[4px] border border-dashed border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer"
            >
              + new recurring task
            </button>

            <p :if={@recurring_tasks == []} class="font-mono text-[12px] text-[#86948F] py-2">
              No recurring tasks yet.
            </p>

            <ul :if={@recurring_tasks != []} class="border border-[#242D31] rounded-[4px] divide-y divide-[#242D31]">
              <li :for={rt <- @recurring_tasks} class="flex items-center gap-3 px-3 py-2.5">
                <span class={["size-1.5 rounded-full shrink-0", priority_dot(rt.priority)]}></span>
                <div class="flex-1 min-w-0">
                  <div class={["text-sm truncate", if(rt.active, do: "text-[#E6ECE9]", else: "text-[#86948F] line-through")]}>
                    {rt.title}
                  </div>
                  <div class="font-mono text-[11px] text-[#86948F]">{recurrence_summary(rt)}</div>
                </div>
                <button
                  phx-click="toggle_recurring_active"
                  phx-value-id={rt.id}
                  class={[
                    "font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border cursor-pointer",
                    if(rt.active,
                      do: "text-[#7FB069] border-[#3C5934]",
                      else: "text-[#86948F] border-[#242D31]"
                    )
                  ]}
                >
                  {if rt.active, do: "active", else: "paused"}
                </button>
                <button
                  phx-click="edit_recurring"
                  phx-value-id={rt.id}
                  class="font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
                >
                  edit
                </button>
                <button
                  phx-click="delete_recurring"
                  phx-value-id={rt.id}
                  class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
                >
                  ×
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :editing, :any, required: true
  attr :form, :any, required: true

  defp recurring_form(assigns) do
    f = assigns.form || %{}
    recurrence = f["recurrence"] || "daily"

    assigns =
      assign(assigns,
        title: f["title"] || "",
        priority: f["priority"] || "medium",
        recurrence: recurrence,
        day_of_week: f["day_of_week"],
        day_of_month: f["day_of_month"]
      )

    ~H"""
    <form phx-submit="save_recurring" phx-change="update_recurring_form" class="space-y-3">
      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">title</label>
        <input
          type="text"
          name="recurring_task[title]"
          value={@title}
          placeholder="Recurring task title…"
          autocomplete="off"
          required
          class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
        />
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">priority</label>
        <div class="flex gap-2">
          <label :for={p <- ["high", "medium", "low"]} class="flex-1">
            <input type="radio" name="recurring_task[priority]" value={p} checked={@priority == p} class="peer hidden" />
            <div class={[
              "flex items-center justify-center gap-1.5 px-2 py-[7px] rounded-[4px] border font-mono text-[11.5px] cursor-pointer transition-colors",
              "border-[#242D31] text-[#86948F] hover:text-[#E6ECE9]",
              "peer-checked:border-transparent",
              "peer-checked:" <> priority_button(p)
            ]}>
              <span class={["size-1.5 rounded-full shrink-0 peer-checked:hidden", priority_dot(p)]}></span>
              {p}
            </div>
          </label>
        </div>
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">repeats</label>
        <select
          name="recurring_task[recurrence]"
          class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none"
        >
          <option :for={r <- ["daily", "weekly", "monthly"]} value={r} selected={@recurrence == r}>{r}</option>
        </select>
      </div>

      <div :if={@recurrence == "weekly"}>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">day of week</label>
        <select
          name="recurring_task[day_of_week]"
          class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none"
        >
          <option :for={d <- 1..7} value={d} selected={@day_of_week == to_string(d)}>{weekday_name(d)}</option>
        </select>
      </div>

      <div :if={@recurrence == "monthly"}>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">day of month</label>
        <input
          type="number"
          min="1"
          max="31"
          name="recurring_task[day_of_month]"
          value={@day_of_month}
          class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none"
        />
      </div>

      <div class="flex items-center justify-end gap-2 pt-2">
        <button
          type="button"
          phx-click="cancel_recurring_form"
          class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
        >
          Back
        </button>
        <button
          type="submit"
          class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
        >
          {if @editing == :new, do: "Create", else: "Save"}
        </button>
      </div>
    </form>
    """
  end

  # ── Boards modal ──────────────────────────────────────────────────────────

  attr :editing, :any, required: true
  attr :form, :any, required: true
  attr :boards, :list, required: true
  attr :confirm_delete, :any, required: true

  defp boards_modal(assigns) do
    ~H"""
    <div
      id="boards-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      phx-window-keydown="close_boards_modal"
      phx-key="escape"
    >
      <div class="absolute inset-0" phx-click="close_boards_modal"></div>
      <div class="relative w-full max-w-[420px] max-h-[80vh] overflow-y-auto rounded-[4px] bg-[#151B1E] border border-[#242D31]">
        <div class="flex items-center justify-between px-4 pt-4 pb-3 border-b border-[#242D31]">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
            boards
          </div>
          <button phx-click="close_boards_modal" class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer">×</button>
        </div>

        <div class="p-4">
          <.board_form :if={@editing} editing={@editing} form={@form} />

          <div :if={!@editing} class="space-y-3">
            <button
              phx-click="new_board"
              class="w-full px-3 py-[9px] rounded-[4px] border border-dashed border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer"
            >
              + new board
            </button>

            <p :if={@boards == []} class="font-mono text-[12px] text-[#86948F] py-2">
              No boards yet.
            </p>

            <ul :if={@boards != []} class="border border-[#242D31] rounded-[4px] divide-y divide-[#242D31]">
              <li :for={board <- @boards} class="px-3 py-2.5">
                <div :if={@confirm_delete != board.id} class="flex items-center gap-3">
                  <div class="flex-1 min-w-0 text-sm truncate text-[#E6ECE9]">{board.name}</div>
                  <button
                    phx-click="edit_board"
                    phx-value-id={board.id}
                    class="font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
                  >
                    edit
                  </button>
                  <button
                    phx-click="confirm_delete_board"
                    phx-value-id={board.id}
                    class="font-mono text-[#86948F] hover:text-[#E0A458] cursor-pointer"
                  >
                    ×
                  </button>
                </div>
                <div :if={@confirm_delete == board.id} class="flex items-center gap-3">
                  <div class="flex-1 min-w-0 font-mono text-[11.5px] text-[#E0A458]">
                    delete "{board.name}"? this deletes every task in it too.
                  </div>
                  <button
                    phx-click="cancel_delete_board"
                    class="font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
                  >
                    cancel
                  </button>
                  <button
                    phx-click="delete_board"
                    phx-value-id={board.id}
                    class="font-mono text-[11px] text-[#E0A458] hover:text-[#c96b4d] cursor-pointer"
                  >
                    delete
                  </button>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :editing, :any, required: true
  attr :form, :any, required: true

  defp board_form(assigns) do
    f = assigns.form || %{}
    assigns = assign(assigns, name: f["name"] || "")

    ~H"""
    <form phx-submit="save_board" phx-change="update_board_form" class="space-y-3">
      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">name</label>
        <input
          type="text"
          name="board[name]"
          value={@name}
          placeholder="Board name…"
          autocomplete="off"
          autofocus
          required
          class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
        />
      </div>

      <div class="flex items-center justify-end gap-2 pt-2">
        <button
          type="button"
          phx-click="cancel_board_form"
          class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
        >
          Back
        </button>
        <button
          type="submit"
          class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
        >
          {if @editing == :new, do: "Create", else: "Save"}
        </button>
      </div>
    </form>
    """
  end
end
