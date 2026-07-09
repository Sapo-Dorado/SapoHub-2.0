defmodule SapoCoreWeb.SettingsLive do
  @moduledoc """
  The tabbed Settings page (hub tab; module tabs arrive with the
  `settings_component()` contract callback in the UI pass).

  Hub tab: Data & deploy (Save all data + amber Deploy button that streams
  `sapohub-deploy` output through a `CommandSession` terminal), snapshot
  history behind a disclosure, secrets status, enabled utilities.
  """

  use SapoCoreWeb, :live_view

  import SapoCoreWeb.Statusline

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

    module_tabs =
      for mod <- Registry.modules(),
          component = mod.settings_component(),
          not is_nil(component) do
        %{id: to_string(mod.id()), title: String.downcase(mod.title()), component: component}
      end

    {:ok,
     assign(socket,
       page_title: "settings",
       deploy_session_id: @deploy_session,
       snapshots: Snapshot.list(),
       secrets: secrets(),
       modules:
         Enum.map(Registry.modules(), &%{id: &1.id(), title: &1.title(), version: &1.version()}),
       module_tabs: module_tabs,
       active_tab: "hub",
       button_choices: button_choices(),
       dashboard_order: dashboard_order(),
       statusline_options: statusline_options(),
       statusline_order_active: SapoCore.Statusline.order_active?(),
       deploy_secret_ready: github_token_set?(),
       saving: false,
       deploy_running: CommandSession.alive?(@deploy_session)
     )}
  end

  defp button_choices do
    for mod <- Registry.modules(),
        mod.ui_routes() != [],
        mod.dashboard_buttons(Registry.config_for(mod)) != [] do
      options =
        [%{id: "default", label: "default — icon + name"}] ++
          Enum.map(
            mod.dashboard_buttons(Registry.config_for(mod)),
            &%{id: &1.id, label: &1.label}
          )

      %{
        module_id: to_string(mod.id()),
        title: String.downcase(mod.title()),
        options: options,
        selected: SapoCore.Prefs.get("dashboard_button.#{mod.id()}", "default")
      }
    end
  end

  # The Settings "Deploy" button always passes --sync-prefs (see
  # deploy_cmd in runtime.exs), which pushes a config-repo commit
  # whenever there's a pending UI-preference overlay to sync. That push
  # needs GITHUB_TOKEN in the secrets file (nix/deploy-script.nix) — no
  # token means sapohub-deploy would commit locally but fail to push.
  # Gate the button on it up front rather than let people hit a git
  # error buried in the terminal output.
  defp github_token_set? do
    (System.get_env("GITHUB_TOKEN") || "") != ""
  end

  # SapoCore.Secrets.status/0 only covers module-declared secrets
  # (core_secrets + each module's required_secrets/0) — GITHUB_TOKEN is
  # deploy infrastructure, not owned by any module, so it's appended
  # here to keep the Settings page's Secrets table complete.
  defp secrets do
    SapoCore.Secrets.status() ++
      [%{var: "GITHUB_TOKEN", required_by: :deploy, set?: github_token_set?()}]
  end

  defp dashboard_order do
    for slot <- SapoCore.Dashboard.ordered_slots() do
      %{id: to_string(slot.id), title: slot.title}
    end
  end

  defp statusline_options do
    shown_ids = SapoCore.Statusline.enabled_items() |> MapSet.new(& &1.id)

    for item <- SapoCore.Statusline.all_items() do
      %{
        id: item.id,
        label: item.label,
        enabled: MapSet.member?(shown_ids, item.id)
      }
    end
  end

  # ── Tabs & prefs ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("set_dashboard_button", %{"module" => module_id, "variant" => variant}, socket) do
    :ok = SapoCore.Prefs.put("dashboard_button.#{module_id}", variant)
    {:noreply, assign(socket, button_choices: button_choices())}
  end

  def handle_event("move_dashboard_tile", %{"id" => id, "dir" => dir}, socket) do
    ids = Enum.map(socket.assigns.dashboard_order, & &1.id)
    from = Enum.find_index(ids, &(&1 == id))
    to = if dir == "up", do: max(from - 1, 0), else: min(from + 1, length(ids) - 1)

    ids
    |> List.delete_at(from)
    |> List.insert_at(to, id)
    |> SapoCore.Dashboard.save_order()

    {:noreply, assign(socket, dashboard_order: dashboard_order())}
  end

  def handle_event("toggle_statusline_item", %{"id" => id}, socket) do
    if socket.assigns.statusline_order_active do
      # An explicit "statusline_order" pref is active and takes full
      # precedence over per-item toggles (see SapoCore.Statusline
      # moduledoc) — flipping one here would silently do nothing, so
      # don't even write it while the override is in effect.
      {:noreply, socket}
    else
      current = SapoCore.Prefs.get("statusline.#{id}", true)
      :ok = SapoCore.Prefs.put("statusline.#{id}", !current)
      {:noreply, assign(socket, statusline_options: statusline_options())}
    end
  end

  # ── Snapshot ───────────────────────────────────────────────────────────────

  def handle_event("save_data", _params, socket) do
    live_view = self()

    Task.Supervisor.start_child(SapoCore.TaskSupervisor, fn ->
      send(live_view, {:snapshot_result, Snapshot.save()})
    end)

    {:noreply, assign(socket, saving: true)}
  end

  # ── Deploy ─────────────────────────────────────────────────────────────────

  def handle_event("deploy", _params, socket) do
    if socket.assigns.deploy_secret_ready do
      {cmd, args} = Application.fetch_env!(:sapo_core, :deploy_cmd)

      case SessionSupervisor.start_command(@deploy_session, cmd, args) do
        {:ok, _pid} ->
          {:noreply, assign(socket, deploy_running: true)}

        {:error, reason} ->
          Logger.error("deploy start failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Deploy failed to start: #{inspect(reason)}")}
      end
    else
      # Belt-and-suspenders: the button is already disabled/hidden from
      # this state client-side, but don't trust that alone.
      {:noreply, put_flash(socket, :error, "Requires the GITHUB_TOKEN secret.")}
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
      <.statusline crumb="settings" items={@statusline} />

      <div class="flex items-center gap-2 px-3 py-2 border-b border-[#242D31] bg-[#151B1E] font-mono text-xs overflow-x-auto">
        <button
          :for={tab <- [%{id: "hub", title: "hub"} | @module_tabs]}
          phx-click="switch_settings_tab"
          phx-value-tab={tab.id}
          class={[
            "px-3 py-[5px] rounded-[3px] whitespace-nowrap cursor-pointer",
            if(tab.id == @active_tab,
              do: "bg-[#0D1113] border border-[#242D31] text-[#E6ECE9]",
              else: "border border-transparent text-[#86948F] hover:text-[#E6ECE9]"
            )
          ]}
        >
          {tab.title}
        </button>
      </div>

      <main :if={@active_tab != "hub"} class="max-w-[980px] mx-auto px-4 py-8">
        <.live_component
          :for={tab <- @module_tabs}
          :if={tab.id == @active_tab}
          module={tab.component}
          id={"settings-#{tab.id}"}
          module_id={tab.id}
        />
      </main>

      <main :if={@active_tab == "hub"} class="max-w-[980px] mx-auto px-4 py-8 space-y-9">
        <Layouts.flash_group flash={@flash} />

        <section>
          <.eyebrow>Data &amp; deploy</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E]">
            <div class="p-4 flex flex-wrap items-center gap-3">
              <button
                phx-click="save_data"
                disabled={@saving}
                class="px-[18px] py-[9px] rounded-[4px] bg-[#7FB069] text-[#0C1409] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#8fbf7b] disabled:opacity-60 cursor-pointer disabled:cursor-not-allowed"
              >
                {if @saving, do: "Saving…", else: "Save all data"}
              </button>
              <button
                phx-click="deploy"
                disabled={@deploy_running or not @deploy_secret_ready}
                title={if @deploy_secret_ready, do: nil, else: "Requires the GITHUB_TOKEN secret"}
                class="px-[18px] py-[9px] rounded-[4px] bg-[#E0A458] text-[#1A1206] text-[12.5px] font-mono font-semibold tracking-[.03em] hover:bg-[#e8b370] disabled:opacity-60 cursor-pointer disabled:cursor-not-allowed"
              >
                {if @deploy_running, do: "Deploying…", else: "Deploy latest"}
              </button>
              <span class="text-[12.5px] text-[#86948F]">
                Deploy rebuilds from GitHub and restarts the hub — output streams below.
              </span>
            </div>
            <p :if={not @deploy_secret_ready} class="px-4 pb-4 text-[12px] font-mono text-[#E0A458]">
              Requires the GITHUB_TOKEN secret.
            </p>

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
          <.eyebrow>Dashboard order</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr :for={{slot, index} <- Enum.with_index(@dashboard_order)} class="border-t first:border-t-0 border-[#242D31]">
                <td class="px-4 py-2.5 font-mono text-[12.5px]">{slot.title}</td>
                <td class="px-4 py-2.5 text-right whitespace-nowrap">
                  <button
                    phx-click="move_dashboard_tile"
                    phx-value-id={slot.id}
                    phx-value-dir="up"
                    disabled={index == 0}
                    class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#86948F] border-[#242D31] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer disabled:opacity-30 disabled:pointer-events-none"
                  >
                    ↑
                  </button>
                  <button
                    phx-click="move_dashboard_tile"
                    phx-value-id={slot.id}
                    phx-value-dir="down"
                    disabled={index == length(@dashboard_order) - 1}
                    class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#86948F] border-[#242D31] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer disabled:opacity-30 disabled:pointer-events-none ml-1"
                  >
                    ↓
                  </button>
                </td>
              </tr>
            </table>
          </div>
        </section>

        <section :if={@button_choices != []}>
          <.eyebrow>Dashboard buttons</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr :for={choice <- @button_choices} class="border-t first:border-t-0 border-[#242D31]">
                <td class="px-4 py-2.5 font-mono text-[12.5px]">{choice.module_id}</td>
                <td class="px-4 py-2.5">
                  <form phx-change="set_dashboard_button">
                    <input type="hidden" name="module" value={choice.module_id} />
                    <select
                      name="variant"
                      class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#86948F] px-2 py-1 focus:border-[#7FB069] focus:outline-none"
                    >
                      <option
                        :for={opt <- choice.options}
                        value={opt.id}
                        selected={opt.id == choice.selected}
                      >
                        {opt.label}
                      </option>
                    </select>
                  </form>
                </td>
              </tr>
            </table>
          </div>
        </section>

        <section>
          <.eyebrow>Statusline</.eyebrow>
          <p :if={@statusline_order_active} class="text-[12px] text-[#86948F] mb-2 font-mono">
            An explicit order override ("statusline_order") is active — it controls what's shown
            below, and these per-item toggles are inert until it's cleared.
          </p>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr :for={opt <- @statusline_options} class="border-t first:border-t-0 border-[#242D31]">
                <td class="px-4 py-2.5 font-mono text-[12.5px]">{opt.id}</td>
                <td class="px-4 py-2.5 text-[#86948F] hidden sm:table-cell">{opt.label}</td>
                <td class="px-4 py-2.5 text-right">
                  <button
                    phx-click="toggle_statusline_item"
                    phx-value-id={opt.id}
                    disabled={@statusline_order_active}
                    class={[
                      "font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border",
                      if(@statusline_order_active,
                        do: "cursor-not-allowed opacity-50",
                        else: "cursor-pointer"
                      ),
                      if(opt.enabled,
                        do: "text-[#7FB069] border-[#3C5934]",
                        else: "text-[#86948F] border-[#242D31]"
                      )
                    ]}
                  >
                    {if opt.enabled, do: "shown", else: "hidden"}
                  </button>
                </td>
              </tr>
            </table>
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
                    class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] text-[#E05C5C] border border-[#6b2b2b]"
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
