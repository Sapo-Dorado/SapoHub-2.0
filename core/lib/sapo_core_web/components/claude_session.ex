defmodule SapoCoreWeb.ClaudeSession do
  @moduledoc """
  Reusable claude session terminal component (ported from v1).

  Renders start/stop controls, error banners, the xterm.js terminal div and
  mobile ESC/CTRL/TAB helper buttons. Events (`start_session`,
  `stop_session`, `terminal_input`, `terminal_resize`, `replay_session`)
  are handled by the parent LiveView.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :session_alive, :boolean, required: true
  attr :starting_session, :boolean, default: false
  attr :session_error, :string, default: nil

  def claude_session(assigns) do
    ~H"""
    <div class="flex flex-col h-full min-h-0">
      <div
        :if={@session_error}
        class="mb-3 p-3 border border-[#6b4f2a] text-[#E0A458] text-xs font-mono rounded-[4px]"
      >
        {@session_error}
      </div>

      <%= if !@session_alive and !@starting_session do %>
        <button
          phx-click="start_session"
          phx-value-session-id={@id}
          class="self-start px-[18px] py-[9px] rounded-[4px] bg-[#7FB069] text-[#0C1409] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#8fbf7b]"
        >
          Start Claude session
        </button>
      <% else %>
        <%!-- Terminal renders during starting_session too so the hook can
             measure real dimensions before the PTY spawns. --%>
        <div class="relative flex-1 min-h-0">
          <div
            id={"terminal-#{@id}"}
            phx-hook="Terminal"
            phx-update="ignore"
            data-session-id={@id}
            class="w-full h-full min-h-[420px] bg-[#0D1113] border border-[#242D31] rounded-[4px] overflow-hidden"
          >
          </div>
          <%!-- Mobile view-as-text: xterm renders to canvas, so native touch
               selection is impossible; this opens a selectable overlay. --%>
          <button
            id={"text-btn-#{@id}"}
            class="absolute top-2 right-2 z-10 px-2 py-1 rounded-[3px] sm:hidden bg-black/40 font-mono text-xs text-white/50 active:text-white/90 touch-manipulation"
          >
            ⎘
          </button>
          <div
            :if={@starting_session}
            class="absolute inset-0 bg-[#0D1113]/90 flex items-center justify-center border border-[#242D31] rounded-[4px]"
          >
            <span class="text-xs font-mono text-[#86948F] animate-pulse">starting session…</span>
          </div>
        </div>
        <div class="mt-2 flex flex-wrap gap-2 sm:hidden">
          <button
            :for={{btn, label} <- mobile_buttons(@id)}
            id={btn}
            class="px-4 py-2 border border-[#242D31] rounded-[4px] text-sm font-mono text-[#E6ECE9] active:bg-[#1A2226]"
          >
            {label}
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp mobile_buttons(id) do
    [
      {"esc-btn-#{id}", "ESC"},
      {"ctrl-btn-#{id}", "CTRL"},
      {"tab-btn-#{id}", "TAB"},
      {"up-btn-#{id}", "↑"},
      {"down-btn-#{id}", "↓"},
      {"paste-btn-#{id}", "Paste"}
    ]
  end
end
