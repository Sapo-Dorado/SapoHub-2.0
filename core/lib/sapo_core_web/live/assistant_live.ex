defmodule SapoCoreWeb.AssistantLive do
  @moduledoc """
  The dedicated full-screen assistant page (ported from v1 AssistantLive).

  Multi-tab claude sessions: the default "main" tab always exists; extra
  tabs are persisted in `TabStore` so reloads reconnect to live sessions.
  Terminal I/O flows JS hook <-> this LiveView <-> SessionRunner PubSub.
  """

  use SapoCoreWeb, :live_view

  import SapoCoreWeb.ClaudeSession
  import SapoCoreWeb.Statusline, only: [statusline: 1]

  require Logger

  alias SapoCore.Assistant.SessionNotifications
  alias SapoCore.Assistant.SessionRunner
  alias SapoCore.Assistant.SessionSupervisor
  alias SapoCore.Assistant.TabStore

  @impl true
  def mount(_params, _session, socket) do
    default_id = TabStore.default_session_id()
    default_tab = build_tab(default_id, "main")

    alive = if connected?(socket), do: SessionRunner.alive?(default_id), else: false
    pending = connected?(socket) && !alive

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{default_id}")
      SessionNotifications.set_enabled(default_id, true)
    end

    default_tab = %{
      default_tab
      | session_alive: alive,
        starting_session: pending,
        pending_auto_start: pending
    }

    extra_tabs =
      for %{session_id: sid, label: label} <- TabStore.list_tabs() do
        tab = build_tab(sid, label)

        if connected?(socket) do
          tab_alive = SessionRunner.alive?(sid)
          Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{sid}")
          SessionNotifications.set_enabled(sid, true)

          %{
            tab
            | session_alive: tab_alive,
              starting_session: !tab_alive,
              pending_auto_start: !tab_alive
          }
        else
          tab
        end
      end

    {:ok,
     assign(socket,
       page_title: "assistant",
       tabs: [default_tab | extra_tabs],
       active_tab_id: default_tab.id
     )}
  end

  # ── Tab management ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("add_tab", _, socket) do
    num = TabStore.next_num()
    session_id = Ecto.UUID.generate()
    label = "session #{num}"
    tab = %{build_tab(session_id, label) | starting_session: true, pending_auto_start: true}

    TabStore.add_tab(session_id, label)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{session_id}")
      SessionNotifications.set_enabled(session_id, true)
    end

    {:noreply,
     socket
     |> assign(tabs: socket.assigns.tabs ++ [tab], active_tab_id: tab.id)
     |> push_event("activate_terminal:#{session_id}", %{})}
  end

  def handle_event("close_tab", %{"id" => tab_id}, socket) do
    if tab = find_tab(socket.assigns.tabs, tab_id) do
      SessionSupervisor.stop_session(tab.session_id)
      TabStore.remove_tab(tab.session_id)
      SessionNotifications.delete(tab.session_id)
    end

    tabs = Enum.reject(socket.assigns.tabs, &(&1.id == tab_id))

    active_tab_id =
      if socket.assigns.active_tab_id == tab_id && tabs != [] do
        List.last(tabs).id
      else
        socket.assigns.active_tab_id
      end

    {:noreply, assign(socket, tabs: tabs, active_tab_id: active_tab_id)}
  end

  def handle_event("switch_tab", %{"id" => tab_id}, socket) do
    socket = assign(socket, active_tab_id: tab_id)

    socket =
      case find_tab(socket.assigns.tabs, tab_id) do
        nil -> socket
        tab -> push_event(socket, "activate_terminal:#{tab.session_id}", %{})
      end

    {:noreply, socket}
  end

  def handle_event("toggle_notify", %{"id" => tab_id}, socket) do
    case find_tab(socket.assigns.tabs, tab_id) do
      nil ->
        {:noreply, socket}

      tab ->
        new_val = !tab.notify_enabled
        SessionNotifications.set_enabled(tab.session_id, new_val)
        {:noreply, update_tab(socket, tab.session_id, &%{&1 | notify_enabled: new_val})}
    end
  end

  # ── Session lifecycle ──────────────────────────────────────────────────────

  def handle_event("start_session", %{"session-id" => session_id}, socket) do
    {:noreply,
     update_tab(socket, session_id, &%{&1 | starting_session: true, session_error: nil})}
  end

  def handle_event("stop_session", %{"session-id" => session_id}, socket) do
    SessionSupervisor.stop_session(session_id)

    {:noreply,
     update_tab(
       socket,
       session_id,
       &%{&1 | session_alive: false, starting_session: false, pending_auto_start: false}
     )}
  end

  # ── Terminal events from the JS hook ───────────────────────────────────────

  def handle_event("terminal_input", %{"data" => data, "session_id" => session_id}, socket) do
    SessionRunner.send_input(session_id, data)
    {:noreply, socket}
  end

  def handle_event(
        "terminal_resize",
        %{"cols" => cols, "rows" => rows, "session_id" => session_id},
        socket
      ) do
    tab = find_tab(socket.assigns.tabs, session_id)

    if tab && tab.session_alive && (cols != tab.terminal_cols || rows != tab.terminal_rows) do
      SessionRunner.resize(session_id, cols, rows)
    end

    socket = update_tab(socket, session_id, &%{&1 | terminal_cols: cols, terminal_rows: rows})

    socket =
      case find_tab(socket.assigns.tabs, session_id) do
        %{pending_auto_start: true} ->
          send(self(), {:do_start_session, session_id})
          update_tab(socket, session_id, &%{&1 | pending_auto_start: false})

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("replay_session", %{"session_id" => session_id}, socket) do
    buffer = SessionRunner.get_buffer(session_id)
    socket = push_event(socket, "terminal_clear:#{session_id}", %{})

    if buffer != "" do
      {:noreply,
       push_event(socket, "terminal_output:#{session_id}", %{data: Base.encode64(buffer)})}
    else
      {:noreply, socket}
    end
  end

  # ── Session startup ────────────────────────────────────────────────────────

  @impl true
  def handle_info({:do_start_session, session_id}, socket) do
    case find_tab(socket.assigns.tabs, session_id) do
      nil ->
        {:noreply, socket}

      tab ->
        cols =
          if is_integer(tab.terminal_cols) && tab.terminal_cols > 0,
            do: tab.terminal_cols,
            else: 220

        rows =
          if is_integer(tab.terminal_rows) && tab.terminal_rows > 0,
            do: tab.terminal_rows,
            else: 30

        case SessionSupervisor.start_session(session_id, cols: cols, rows: rows) do
          {:ok, _} ->
            {:noreply,
             update_tab(socket, session_id, &%{&1 | starting_session: false, session_alive: true})}

          {:error, reason} ->
            Logger.error("AssistantLive session #{session_id} failed: #{inspect(reason)}")

            {:noreply,
             update_tab(
               socket,
               session_id,
               &%{
                 &1
                 | starting_session: false,
                   session_error: "Failed to start session: #{inspect(reason)}"
               }
             )}
        end
    end
  end

  # ── PubSub from SessionRunner ──────────────────────────────────────────────

  def handle_info({:session_output, session_id, data}, socket) do
    {:noreply, push_event(socket, "terminal_output:#{session_id}", %{data: Base.encode64(data)})}
  end

  def handle_info({:session_exit, session_id, code}, socket) do
    {:noreply,
     socket
     |> update_tab(session_id, &%{&1 | session_alive: false})
     |> push_event("session_exit:#{session_id}", %{code: code})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[100dvh] bg-[#0D1113]">
      <.statusline crumb="assistant" items={@statusline} />

      <%!-- Tab bar --%>
      <div class="flex items-center gap-2 px-3 py-2 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs overflow-x-auto shrink-0">
        <div
          :for={tab <- @tabs}
          class={[
            "flex items-center gap-1.5 px-3 py-[5px] rounded-[3px] whitespace-nowrap",
            if(tab.id == @active_tab_id,
              do: "text-[#E6ECE9] bg-[#0D1113] border border-[#242D31]",
              else: "text-[#86948F] border border-transparent hover:text-[#E6ECE9] cursor-pointer"
            )
          ]}
        >
          <button phx-click="switch_tab" phx-value-id={tab.id} class="flex items-center gap-[7px] cursor-pointer">
            <span class={[
              "w-1.5 h-1.5 rounded-full inline-block",
              if(tab.session_alive, do: "bg-[#7FB069]", else: "bg-[#3C5934]")
            ]}>
            </span>
            {tab.label}
          </button>
          <button
            phx-click="toggle_notify"
            phx-value-id={tab.id}
            title={if tab.notify_enabled, do: "Notifications on", else: "Notifications off"}
            class={[
              "leading-none cursor-pointer",
              if(tab.notify_enabled, do: "text-[#7FB069]", else: "text-[#3C5934] line-through")
            ]}
          >
            n
          </button>
          <button
            :if={length(@tabs) > 1}
            phx-click="close_tab"
            phx-value-id={tab.id}
            class="text-[#86948F] hover:text-[#E0A458] leading-none cursor-pointer"
          >
            ×
          </button>
        </div>
        <button
          phx-click="add_tab"
          class="px-3 py-[5px] text-[#86948F] hover:text-[#E6ECE9] whitespace-nowrap cursor-pointer"
        >
          + new
        </button>
      </div>

      <%!-- Terminal panes — all mounted, inactive hidden so hooks stay alive --%>
      <div class="flex-1 min-h-0 p-3">
        <div
          :for={tab <- @tabs}
          class={["h-full", if(tab.id == @active_tab_id, do: "", else: "hidden")]}
        >
          <.claude_session
            id={tab.session_id}
            session_alive={tab.session_alive}
            starting_session={tab.starting_session}
            session_error={tab.session_error}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp build_tab(session_id, label) do
    %{
      id: session_id,
      label: label,
      session_id: session_id,
      session_alive: false,
      starting_session: false,
      pending_auto_start: false,
      terminal_cols: nil,
      terminal_rows: nil,
      session_error: nil,
      notify_enabled: true
    }
  end

  defp find_tab(tabs, id), do: Enum.find(tabs, &(&1.id == id))

  defp update_tab(socket, session_id, fun) do
    tabs =
      Enum.map(socket.assigns.tabs, fn tab ->
        if tab.session_id == session_id, do: fun.(tab), else: tab
      end)

    assign(socket, tabs: tabs)
  end
end
