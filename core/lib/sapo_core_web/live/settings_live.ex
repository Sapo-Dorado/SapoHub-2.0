defmodule SapoCoreWeb.SettingsLive do
  @moduledoc """
  The tabbed Settings page (hub tab; module tabs arrive with the
  `settings_component()` contract callback in the UI pass).

  Hub tab: Data & deploy (Save all data + amber Deploy button that streams
  `sapohub-deploy` output through a `CommandSession` terminal), snapshot
  history behind a disclosure, secrets status, enabled utilities.
  """

  use SapoCoreWeb, :live_view

  require Logger

  alias SapoCore.Assistant.CommandSession
  alias SapoCore.Assistant.SessionSupervisor
  alias SapoCore.Generated.Registry
  alias SapoCore.Snapshot

  @deploy_session "deploy"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{@deploy_session}")
    end

    {:ok,
     assign(socket,
       page_title: "settings",
       deploy_session_id: @deploy_session,
       snapshots: Snapshot.list(),
       secrets: SapoCore.Secrets.status(),
       modules:
         Enum.map(Registry.modules(), &%{id: &1.id(), title: &1.title(), version: &1.version()}),
       saving: false,
       deploy_running: CommandSession.alive?(@deploy_session)
     )}
  end

  # ── Snapshot ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("save_data", _params, socket) do
    live_view = self()

    Task.Supervisor.start_child(SapoCore.TaskSupervisor, fn ->
      send(live_view, {:snapshot_result, Snapshot.save()})
    end)

    {:noreply, assign(socket, saving: true)}
  end

  # ── Deploy ─────────────────────────────────────────────────────────────────

  def handle_event("deploy", _params, socket) do
    {cmd, args} = Application.fetch_env!(:sapo_core, :deploy_cmd)

    case SessionSupervisor.start_command(@deploy_session, cmd, args) do
      {:ok, _pid} ->
        {:noreply, assign(socket, deploy_running: true)}

      {:error, reason} ->
        Logger.error("deploy start failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Deploy failed to start: #{inspect(reason)}")}
    end
  end

  # ── Terminal events from the JS hook (deploy pane) ─────────────────────────

  def handle_event("terminal_input", %{"data" => data, "session_id" => sid}, socket) do
    CommandSession.send_input(sid, data)
    {:noreply, socket}
  end

  def handle_event("terminal_resize", %{"cols" => c, "rows" => r, "session_id" => sid}, socket) do
    if CommandSession.alive?(sid), do: CommandSession.resize(sid, c, r)
    {:noreply, socket}
  end

  def handle_event("replay_session", %{"session_id" => sid}, socket) do
    buffer = CommandSession.get_buffer(sid)
    socket = push_event(socket, "terminal_clear:#{sid}", %{})

    if buffer != "" do
      {:noreply, push_event(socket, "terminal_output:#{sid}", %{data: Base.encode64(buffer)})}
    else
      {:noreply, socket}
    end
  end

  # ── Async results / PubSub ─────────────────────────────────────────────────

  @impl true
  def handle_info({:snapshot_result, result}, socket) do
    socket =
      case result do
        {:ok, path} ->
          socket
          |> put_flash(:info, "Saved #{Path.basename(path)}")
          |> assign(snapshots: Snapshot.list())

        {:error, reason} ->
          put_flash(socket, :error, "Snapshot failed: #{inspect(reason)}")
      end

    {:noreply, assign(socket, saving: false)}
  end

  def handle_info({:session_output, sid, data}, socket) do
    {:noreply, push_event(socket, "terminal_output:#{sid}", %{data: Base.encode64(data)})}
  end

  def handle_info({:session_exit, sid, code}, socket) do
    {:noreply,
     socket
     |> assign(deploy_running: false)
     |> push_event("session_exit:#{sid}", %{code: code})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <nav class="flex items-center h-[38px] px-4 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs">
        <.link navigate={~p"/"} class="text-[#7FB069] font-semibold">sapohub</.link>
        <span class="text-[#86948F] px-2">/</span>
        <span>settings</span>
      </nav>

      <div class="flex items-center gap-2 px-3 py-2 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs">
        <span class="px-3 py-[5px] rounded-[3px] bg-[#0D1113] border border-[#242D31]">hub</span>
        <%!-- module settings tabs land with the settings_component() callback --%>
      </div>

      <main class="max-w-[980px] mx-auto px-4 py-8 space-y-9">
        <Layouts.flash_group flash={@flash} />

        <section>
          <.eyebrow>Data &amp; deploy</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E]">
            <div class="p-4 flex flex-wrap items-center gap-3">
              <button
                phx-click="save_data"
                disabled={@saving}
                class="px-[18px] py-[9px] rounded-[4px] bg-[#7FB069] text-[#0C1409] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#8fbf7b] disabled:opacity-60"
              >
                {if @saving, do: "Saving…", else: "Save all data"}
              </button>
              <button
                phx-click="deploy"
                disabled={@deploy_running}
                class="px-[18px] py-[9px] rounded-[4px] bg-[#E0A458] text-[#1A1206] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#e8b370] disabled:opacity-60"
              >
                {if @deploy_running, do: "Deploying…", else: "Deploy latest"}
              </button>
              <span class="text-[12.5px] text-[#86948F]">
                Deploy rebuilds from GitHub and restarts the hub — output streams below.
              </span>
            </div>

            <details>
              <summary class="px-4 py-[11px] border-t border-[#242D31] font-mono text-xs text-[#86948F] cursor-pointer hover:text-[#E6ECE9] select-none">
                recent snapshots ({length(@snapshots)})
              </summary>
              <table class="w-full text-[13.5px]">
                <tr :for={snap <- @snapshots} class="border-t border-[#242D31]">
                  <td class="px-4 py-2.5 font-mono text-[12.5px]">{snap.name}</td>
                  <td class="px-4 py-2.5 text-[#86948F] hidden sm:table-cell">
                    {format_size(snap.size)}
                  </td>
                  <td class="px-4 py-2.5 text-right">
                    <a
                      href={~p"/api/snapshot/#{snap.name}"}
                      class="font-mono text-[12.5px] text-[#7FB069]"
                    >
                      download
                    </a>
                  </td>
                </tr>
              </table>
            </details>
          </div>

          <div :if={@deploy_running} class="mt-3">
            <div
              id={"terminal-#{@deploy_session_id}"}
              phx-hook="Terminal"
              phx-update="ignore"
              data-session-id={@deploy_session_id}
              class="w-full h-[320px] bg-[#0D1113] border border-[#242D31] rounded-[4px] overflow-hidden"
            >
            </div>
          </div>
        </section>

        <section>
          <.eyebrow>Secrets</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr class="bg-[#0D1113] font-mono text-[11px] uppercase tracking-[.1em] text-[#86948F]">
                <th class="px-4 py-2.5 text-left">Variable</th>
                <th class="px-4 py-2.5 text-left hidden sm:table-cell">Required by</th>
                <th class="px-4 py-2.5 text-left">Status</th>
              </tr>
              <tr :for={s <- @secrets} class="border-t border-[#242D31]">
                <td class="px-4 py-2.5 font-mono text-[12.5px]">{s.var}</td>
                <td class="px-4 py-2.5 text-[#86948F] hidden sm:table-cell">{s.required_by}</td>
                <td class="px-4 py-2.5">
                  <span
                    :if={s.set?}
                    class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] text-[#7FB069] border border-[#3C5934]"
                  >
                    set
                  </span>
                  <span
                    :if={!s.set?}
                    class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] text-[#E0A458] border border-[#6b4f2a]"
                  >
                    missing
                  </span>
                </td>
              </tr>
              <tr :if={@secrets == []}>
                <td colspan="3" class="px-4 py-2.5 text-[#86948F]">No secrets declared.</td>
              </tr>
            </table>
          </div>
        </section>

        <section>
          <.eyebrow>Enabled utilities</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr :for={mod <- @modules} class="border-t first:border-t-0 border-[#242D31]">
                <td class="px-4 py-2.5 font-mono text-[12.5px]">{mod.id}</td>
                <td class="px-4 py-2.5 text-[#86948F] hidden sm:table-cell">{mod.title}</td>
                <td class="px-4 py-2.5 text-right font-mono text-[12.5px] text-[#86948F]">
                  {mod.version}
                </td>
              </tr>
            </table>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp eyebrow(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 mb-3.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
      {render_slot(@inner_block)}
      <span class="h-px flex-1 bg-[#242D31]"></span>
    </div>
    """
  end

  defp format_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes) when bytes >= 1024, do: "#{div(bytes, 1024)} KB"
  defp format_size(bytes), do: "#{bytes} B"
end
