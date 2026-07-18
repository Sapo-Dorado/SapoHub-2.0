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
  alias SapoCore.Notify
  alias SapoCore.Notify.Destination
  alias SapoCore.Snapshot

  @deploy_session "deploy"

  # Secrets the Settings page will let you type in and write (via
  # sapohub-set-secret, nix/secret-script.nix) rather than requiring SSH.
  # Keep in sync with that script's own allowlist — each side checks
  # independently on purpose, neither trusts the other alone.
  @settable_secrets ["GITHUB_TOKEN"]

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
       remote_control_enabled: SapoCore.Prefs.get("assistant.remote_control", false),
       deploy_secret_ready: github_token_set?(),
       editing_secret: nil,
       secret_saving: false,
       settable_secrets: @settable_secrets,
       saving: false,
       deploy_running: CommandSession.alive?(@deploy_session),
       last_deploy: read_last_deploy(),
       destinations: Notify.list_destinations(),
       editing_destination: nil,
       destination_form: nil
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
  # GITHUB_TOKEN is checked via sapohub-set-secret --status (reads the
  # secrets file fresh, as root) rather than System.get_env — the app
  # process's own env is only refreshed on restart, but this secret can
  # now be written live from the Settings page below, and the badge
  # should reflect that immediately rather than lying until a restart.
  defp github_token_set?, do: secret_status("GITHUB_TOKEN")

  # SapoCore.Secrets.status/0 only covers module-declared secrets
  # (core_secrets + each module's required_secrets/0) — GITHUB_TOKEN is
  # deploy infrastructure, not owned by any module, so it's appended
  # here to keep the Settings page's Secrets table complete.
  defp secrets do
    SapoCore.Secrets.status() ++
      [%{var: "GITHUB_TOKEN", required_by: :deploy, set?: github_token_set?()}]
  end

  defp secret_status(var) do
    {cmd, args} = Application.fetch_env!(:sapo_core, :set_secret_cmd)
    exe = System.find_executable(cmd) || cmd

    case System.cmd(exe, args ++ ["--status", var]) do
      {out, 0} -> String.trim(out) == "set"
      _ -> false
    end
  end

  # Writes one secret via a short-lived Port (not System.cmd — the value
  # has to go over stdin, never argv, since argv is visible to any other
  # local user via `ps`). The script only ever needs one line terminated
  # by \n, so the port is never closed early: closing it would also cut
  # off our ability to read its exit status/output back.
  defp secret_set(var, value) do
    {cmd, args} = Application.fetch_env!(:sapo_core, :set_secret_cmd)
    exe = System.find_executable(cmd) || cmd

    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        args: args ++ ["--set", var]
      ])

    Port.command(port, value <> "\n")
    await_secret_port(port, "")
  end

  defp await_secret_port(port, acc) do
    receive do
      {^port, {:data, data}} -> await_secret_port(port, acc <> data)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, code}} -> {:error, "sapohub-set-secret exited #{code}"}
    after
      10_000 ->
        Port.close(port)
        {:error, "timed out"}
    end
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

  def handle_event("toggle_remote_control", _params, socket) do
    new_val = !socket.assigns.remote_control_enabled
    :ok = SapoCore.Prefs.put("assistant.remote_control", new_val)
    {:noreply, assign(socket, remote_control_enabled: new_val)}
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

  # ── Secrets ────────────────────────────────────────────────────────────────

  def handle_event("edit_secret", %{"var" => var}, socket) do
    if var in @settable_secrets do
      {:noreply, assign(socket, editing_secret: var)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_secret", _params, socket) do
    {:noreply, assign(socket, editing_secret: nil)}
  end

  def handle_event("save_secret", %{"var" => var, "value" => value}, socket) do
    cond do
      var not in @settable_secrets ->
        {:noreply, put_flash(socket, :error, "Can't set #{var} from here.")}

      String.trim(value) == "" ->
        {:noreply, put_flash(socket, :error, "Value can't be empty.")}

      true ->
        socket = assign(socket, secret_saving: true)

        case secret_set(var, String.trim(value)) do
          :ok ->
            {:noreply,
             socket
             |> assign(
               secret_saving: false,
               editing_secret: nil,
               secrets: secrets(),
               deploy_secret_ready: github_token_set?()
             )
             |> put_flash(:info, "#{var} saved.")}

          {:error, reason} ->
            Logger.error("secret set failed: #{inspect(reason)}")

            {:noreply,
             socket
             |> assign(secret_saving: false)
             |> put_flash(:error, "Couldn't save #{var}.")}
        end
    end
  end

  # ── Notification destinations ───────────────────────────────────────────────

  def handle_event("new_destination", _params, socket) do
    changeset = Destination.changeset(%Destination{channel: "telegram", config: %{}}, %{})

    {:noreply,
     assign(socket, editing_destination: :new, destination_form: to_form(changeset, as: "destination"))}
  end

  def handle_event("edit_destination", %{"id" => id}, socket) do
    dest = Notify.get_destination!(id)
    changeset = Destination.changeset(dest, %{})

    {:noreply,
     assign(socket, editing_destination: dest, destination_form: to_form(changeset, as: "destination"))}
  end

  def handle_event("cancel_edit_destination", _params, socket) do
    {:noreply, assign(socket, editing_destination: nil, destination_form: nil)}
  end

  def handle_event("validate_destination", %{"destination" => params}, socket) do
    base =
      case socket.assigns.editing_destination do
        :new -> %Destination{}
        %Destination{} = dest -> dest
      end

    changeset = base |> Destination.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, destination_form: to_form(changeset, as: "destination"))}
  end

  def handle_event("save_destination", %{"destination" => params}, socket) do
    result =
      case socket.assigns.editing_destination do
        :new -> Notify.create_destination(params)
        %Destination{} = dest -> Notify.update_destination(dest, params)
      end

    case result do
      {:ok, _dest} ->
        {:noreply,
         socket
         |> assign(
           destinations: Notify.list_destinations(),
           editing_destination: nil,
           destination_form: nil
         )
         |> put_flash(:info, "Destination saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, destination_form: to_form(changeset, as: "destination"))}
    end
  end

  def handle_event("delete_destination", %{"id" => id}, socket) do
    dest = Notify.get_destination!(id)
    {:ok, _} = Notify.delete_destination(dest)
    {:noreply, assign(socket, destinations: Notify.list_destinations())}
  end

  def handle_event("set_default_destination", %{"id" => id}, socket) do
    dest = Notify.get_destination!(id)
    {:ok, _} = Notify.set_default_destination(dest)
    {:noreply, assign(socket, destinations: Notify.list_destinations())}
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
    socket =
      if sid == @deploy_session do
        # sapohub-deploy (nix/deploy-script.nix) writes last-deploy.json
        # from inside its detached rebuild unit before this outer
        # session's process exits, so the file is already current by the
        # time this message arrives.
        assign(socket, last_deploy: read_last_deploy())
      else
        socket
      end

    {:noreply,
     socket
     |> assign(deploy_running: false)
     |> push_event("session_exit:#{sid}", %{code: code})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Last deploy status ──────────────────────────────────────────────────────

  defp read_last_deploy do
    path = Application.get_env(:sapo_core, :last_deploy_file)

    with true <- is_binary(path),
         {:ok, content} <- File.read(path),
         {:ok, %{"at" => at, "status" => status} = decoded} <- Jason.decode(content),
         {:ok, dt, _offset} <- DateTime.from_iso8601(at) do
      %{at: dt, status: status, warnings: Map.get(decoded, "warnings", [])}
    else
      _ -> nil
    end
  end

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
            <p :if={@last_deploy && !@deploy_running} class="px-4 pb-4 text-[12px] font-mono">
              <span class="text-[#86948F]">
                Last deployed {format_deploy_time(@last_deploy.at)} —
              </span>
              <span class={
                cond do
                  @last_deploy.status != "success" -> "text-[#E05C5C]"
                  @last_deploy.warnings != [] -> "text-[#E0A458]"
                  true -> "text-[#7FB069]"
                end
              }>
                {@last_deploy.status}
              </span>
              <span :if={@last_deploy.warnings != []} class="block mt-1 text-[#E0A458]">
                <span :for={w <- @last_deploy.warnings}>⚠ {w}</span>
              </span>
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
              <tr
                :for={{slot, index} <- Enum.with_index(@dashboard_order)}
                class="border-t first:border-t-0 border-[#242D31]"
              >
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
          <.eyebrow>Assistant</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <div class="flex items-center justify-between gap-3 px-4 py-2.5">
              <div>
                <p class="font-mono text-[12.5px]">Remote Control</p>
                <p class="text-[12px] text-[#86948F] mt-0.5">
                  New assistant sessions start with <code>--remote-control</code>, reusing the
                  tab's name, so they can be attached from claude.ai/code or the Claude mobile
                  app. Requires each session to be logged in with a claude.ai subscription — API
                  key auth doesn't support it, and until login happens the session just starts
                  normally. Takes effect for new sessions only.
                </p>
              </div>
              <button
                phx-click="toggle_remote_control"
                class={[
                  "font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border shrink-0 cursor-pointer",
                  if(@remote_control_enabled,
                    do: "text-[#7FB069] border-[#3C5934]",
                    else: "text-[#86948F] border-[#242D31]"
                  )
                ]}
              >
                {if @remote_control_enabled, do: "enabled", else: "disabled"}
              </button>
            </div>
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
                  <div :if={@editing_secret != s.var} class="flex items-center justify-between gap-2">
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
                    <button
                      :if={s.var in @settable_secrets}
                      phx-click="edit_secret"
                      phx-value-var={s.var}
                      title={if s.set?, do: "Replace #{s.var}", else: "Set #{s.var}"}
                      class="p-1 rounded-[3px] text-[#86948F] hover:text-[#7FB069] hover:bg-[#1a2419] cursor-pointer"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
                  </div>
                  <form
                    :if={@editing_secret == s.var}
                    phx-submit="save_secret"
                    class="flex items-center gap-2"
                  >
                    <input type="hidden" name="var" value={s.var} />
                    <input
                      type="password"
                      name="value"
                      autocomplete="off"
                      placeholder={"paste #{s.var}"}
                      class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none w-[220px]"
                    />
                    <button
                      type="submit"
                      disabled={@secret_saving}
                      class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#7FB069] border-[#3C5934] hover:bg-[#1a2419] cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      {if @secret_saving, do: "saving…", else: "save"}
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_edit_secret"
                      disabled={@secret_saving}
                      class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#86948F] border-[#242D31] hover:text-[#E6ECE9] cursor-pointer disabled:opacity-50"
                    >
                      cancel
                    </button>
                  </form>
                </td>
              </tr>
              <tr :if={@secrets == []}>
                <td colspan="3" class="px-4 py-2.5 text-[#86948F]">No secrets declared.</td>
              </tr>
            </table>
          </div>
        </section>

        <section>
          <.eyebrow>Notification destinations</.eyebrow>
          <div class="border border-[#242D31] rounded-[4px] bg-[#151B1E] overflow-hidden">
            <table class="w-full text-[13.5px]">
              <tr class="bg-[#0D1113] font-mono text-[11px] uppercase tracking-[.1em] text-[#86948F]">
                <th class="px-4 py-2.5 text-left">Name</th>
                <th class="px-4 py-2.5 text-left hidden sm:table-cell">Channel</th>
                <th class="px-4 py-2.5 text-left">Default</th>
                <th class="px-4 py-2.5 text-right">Actions</th>
              </tr>
              <%= for dest <- @destinations do %>
                <tr :if={!editing?(@editing_destination, dest.id)} class="border-t border-[#242D31]">
                  <td class="px-4 py-2.5 font-mono text-[12.5px]">{dest.name}</td>
                  <td class="px-4 py-2.5 text-[#86948F] hidden sm:table-cell">{dest.channel}</td>
                  <td class="px-4 py-2.5">
                    <span
                      :if={dest.is_default}
                      class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] text-[#7FB069] border border-[#3C5934]"
                    >
                      default
                    </span>
                    <button
                      :if={!dest.is_default}
                      phx-click="set_default_destination"
                      phx-value-id={dest.id}
                      class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#86948F] border-[#242D31] hover:text-[#7FB069] hover:border-[#3C5934] cursor-pointer"
                    >
                      set default
                    </button>
                  </td>
                  <td class="px-4 py-2.5 text-right whitespace-nowrap">
                    <button
                      phx-click="edit_destination"
                      phx-value-id={dest.id}
                      title={"Edit #{dest.name}"}
                      class="p-1 rounded-[3px] text-[#86948F] hover:text-[#7FB069] hover:bg-[#1a2419] cursor-pointer"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
                    <button
                      phx-click="delete_destination"
                      phx-value-id={dest.id}
                      data-confirm={"Delete #{dest.name}?"}
                      title={"Delete #{dest.name}"}
                      class="p-1 rounded-[3px] text-[#86948F] hover:text-[#E05C5C] hover:bg-[#241414] cursor-pointer"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
                <tr :if={editing?(@editing_destination, dest.id)} class="border-t border-[#242D31]">
                  <td colspan="4" class="px-4 py-3">
                    <.destination_form form={@destination_form} />
                  </td>
                </tr>
              <% end %>
              <tr :if={@destinations == [] and @editing_destination != :new}>
                <td colspan="4" class="px-4 py-2.5 text-[#86948F]">No destinations configured.</td>
              </tr>
              <tr :if={@editing_destination == :new} class="border-t border-[#242D31]">
                <td colspan="4" class="px-4 py-3">
                  <.destination_form form={@destination_form} />
                </td>
              </tr>
            </table>
          </div>
          <button
            :if={@editing_destination == nil}
            phx-click="new_destination"
            class="mt-3 font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#7FB069] border-[#3C5934] hover:bg-[#1a2419] cursor-pointer"
          >
            + add destination
          </button>
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

  defp editing?(%Destination{id: id}, id), do: true
  defp editing?(_, _), do: false

  attr :form, :any, required: true

  defp destination_form(assigns) do
    ~H"""
    <.form for={@form} phx-change="validate_destination" phx-submit="save_destination" class="space-y-2.5">
      <div class="flex flex-wrap gap-2.5">
        <input
          type="text"
          name={@form[:name].name}
          value={@form[:name].value}
          placeholder="name"
          class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none w-[180px]"
        />
        <select
          name={@form[:channel].name}
          class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none"
        >
          <option :for={c <- Destination.channels()} value={c} selected={c == @form[:channel].value}>
            {c}
          </option>
        </select>
      </div>

      <div :if={@form[:channel].value == "telegram"} class="flex flex-wrap gap-2.5">
        <input
          type="text"
          name={@form[:config].name <> "[bot_token]"}
          value={Map.get(@form[:config].value || %{}, "bot_token", "")}
          placeholder="bot token"
          class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none w-[220px]"
        />
        <input
          type="text"
          name={@form[:config].name <> "[chat_id]"}
          value={Map.get(@form[:config].value || %{}, "chat_id", "")}
          placeholder="chat id"
          class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none w-[160px]"
        />
      </div>

      <div :if={@form[:channel].value == "discord"} class="flex flex-wrap gap-2.5">
        <input
          type="text"
          name={@form[:config].name <> "[webhook_url]"}
          value={Map.get(@form[:config].value || %{}, "webhook_url", "")}
          placeholder="webhook url"
          class="bg-[#0D1113] border border-[#242D31] rounded-[3px] font-mono text-[12px] text-[#E6ECE9] px-2 py-1 focus:border-[#7FB069] focus:outline-none w-[320px]"
        />
      </div>

      <p :for={{field, {msg, _opts}} <- @form.errors} class="text-[12px] font-mono text-[#E05C5C]">
        {field}: {msg}
      </p>

      <div class="flex items-center gap-2">
        <button
          type="submit"
          class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#7FB069] border-[#3C5934] hover:bg-[#1a2419] cursor-pointer"
        >
          save
        </button>
        <button
          type="button"
          phx-click="cancel_edit_destination"
          class="font-mono text-[11px] px-[7px] py-[2px] rounded-[3px] border text-[#86948F] border-[#242D31] hover:text-[#E6ECE9] cursor-pointer"
        >
          cancel
        </button>
      </div>
    </.form>
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

  # Shown in the instance's configured display timezone
  # (services.sapohub.timezone, default UTC) rather than the browser's —
  # this page is about the server's own deploy history, and the server has
  # no reliable notion of the browser's timezone anyway.
  defp format_deploy_time(%DateTime{} = dt) do
    local = SapoCore.Time.local(dt)
    Calendar.strftime(local, "%b %-d, %Y %H:%M") <> " " <> local.zone_abbr
  end
end
