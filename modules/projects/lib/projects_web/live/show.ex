defmodule ProjectsWeb.Live.Show do
  @moduledoc """
  Project detail page: repo header (name/url/last-pulled), Pull button,
  discovered scripts (with inline required/optional param inputs and
  live-streaming output), and a Settings link. Ported from v1's
  `ProjectDetailLive`.

  Sudo scripts are shown (flagged, not hidden) but have no Run control —
  see `Projects.Module`'s moduledoc for why sudo-script execution isn't
  implemented in this version.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)

    {:ok,
     socket
     |> assign(
       project: project,
       scripts: Projects.list_scripts(project),
       pulling: false,
       pull_error: nil,
       running_scripts: %{},
       inline_params: %{}
     )}
  end

  @impl true
  def handle_event("pull", _, socket) do
    send(self(), :do_pull)
    {:noreply, assign(socket, pulling: true, pull_error: nil)}
  end

  def handle_event("run_script", %{"file" => file}, socket) do
    script = Enum.find(socket.assigns.scripts, &(&1.file == file))
    start_script(socket, script)
  end

  def handle_event("update_inline_params", %{"file" => file} = params, socket) do
    inline_for_script = Map.get(params, "inline", %{})
    inline = Map.put(socket.assigns.inline_params, file, inline_for_script)
    {:noreply, assign(socket, inline_params: inline)}
  end

  def handle_event("clear_script_output", %{"runner_id" => runner_id}, socket) do
    {:noreply, assign(socket, running_scripts: Map.delete(socket.assigns.running_scripts, runner_id))}
  end

  @impl true
  def handle_info(:do_pull, socket) do
    case pull_and_update(socket) do
      {:ok, socket} -> {:noreply, assign(socket, pulling: false, pull_error: nil)}
      {:error, reason, socket} -> {:noreply, assign(socket, pulling: false, pull_error: reason)}
    end
  end

  def handle_info({:script_output, runner_id, data}, socket) do
    case socket.assigns.running_scripts[runner_id] do
      nil ->
        {:noreply, socket}

      runner ->
        updated = Map.update!(runner, :output, &(&1 ++ [data]))
        {:noreply, assign(socket, running_scripts: Map.put(socket.assigns.running_scripts, runner_id, updated))}
    end
  end

  def handle_info({:script_done, runner_id, code}, socket) do
    case socket.assigns.running_scripts[runner_id] do
      nil ->
        {:noreply, socket}

      runner ->
        status = if code == 0, do: :done, else: :error
        running = Map.put(socket.assigns.running_scripts, runner_id, Map.put(runner, :status, status))
        {:noreply, assign(socket, running_scripts: running)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private ──────────────────────────────────────────────────────────────

  defp pull_and_update(socket) do
    case Projects.pull_project(socket.assigns.project) do
      {:ok, updated} ->
        {:ok, assign(socket, project: updated, scripts: Projects.list_scripts(updated))}

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  defp start_script(socket, %{sudo: true}), do: {:noreply, socket}

  defp start_script(socket, script) do
    project = socket.assigns.project
    inline = Map.get(socket.assigns.inline_params, script.file, %{})

    configured =
      project.params
      |> Enum.filter(&(&1.key in (script.params ++ script.optional_params)))
      |> Map.new(&{&1.key, &1.value})

    inline_to_pass =
      inline
      |> Enum.filter(fn {k, v} -> k in script.params or (k in script.optional_params and String.trim(v) != "") end)
      |> Map.new()

    param_values = Map.merge(configured, inline_to_pass)

    case Projects.run_script_live(project, script, param_values) do
      {:ok, runner_id, project} ->
        SapoKit.PubSub.subscribe("projects:run:#{runner_id}")

        running =
          Map.put(socket.assigns.running_scripts, runner_id, %{name: script.name, output: [], status: :running})

        {:noreply, assign(socket, project: project, scripts: Projects.list_scripts(project), running_scripts: running)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start script: #{inspect(reason)}")}
    end
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(%DateTime{} = dt), do: dt |> DateTime.to_naive() |> NaiveDateTime.to_string()

  defp clean_output(text) do
    text
    |> String.replace(~r/\e\[[0-9;]*[a-zA-Z]/, "")
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb={"projects / #{@project.name}"} items={@statusline} />

      <main class="max-w-[820px] mx-auto px-4 py-6 space-y-7">
        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
          <div class="min-w-0">
            <h1 class="font-mono text-[15px] font-bold uppercase tracking-widest truncate">{@project.name}</h1>
            <div class="font-mono text-[11.5px] text-[#86948F] mt-1 truncate">{@project.github_url}</div>
            <div class="font-mono text-[11px] text-[#5c6b66] mt-1">last pulled: {format_datetime(@project.last_pulled_at)}</div>
          </div>
          <div class="flex gap-2 shrink-0">
            <button
              phx-click="pull"
              disabled={@pulling}
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#E6ECE9] hover:bg-[#1A2226] disabled:opacity-50 cursor-pointer"
            >
              {if @pulling, do: "Pulling…", else: "Pull"}
            </button>
            <.link
              navigate={"/projects/#{@project.id}/settings"}
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#E6ECE9] hover:bg-[#1A2226]"
            >
              Settings
            </.link>
          </div>
        </div>

        <div :if={@pull_error} class="p-3 rounded-[4px] border border-[#E0A458] text-[#E0A458] text-xs font-mono whitespace-pre-wrap">
          {@pull_error}
        </div>

        <div :if={@scripts != []}>
          <div class="eyebrow font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-3">
            scripts
          </div>
          <div class="space-y-2">
            <div :for={script <- @scripts} class="rounded-[4px] border border-[#242D31] bg-[#151B1E] p-3">
              <div class="flex items-center justify-between mb-2 gap-2">
                <span class="font-mono text-sm truncate">{script.name}</span>
                <div class="flex items-center gap-2 shrink-0">
                  <span :if={script.sudo} class="font-mono text-[11px] text-[#E0A458] border border-[#E0A458]/50 rounded-[3px] px-1.5 py-0.5">
                    sudo · not runnable
                  </span>
                  <button
                    :if={!script.sudo and script.params == [] and script.optional_params == []}
                    phx-click="run_script"
                    phx-value-file={script.file}
                    class="px-3 py-1 rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#E6ECE9] hover:bg-[#1A2226] cursor-pointer"
                  >
                    Run
                  </button>
                </div>
              </div>

              <p :if={script.sudo} class="font-mono text-[11px] text-[#86948F]">
                This script requires root and cannot be run from the Projects module — run it manually on the host.
              </p>

              <form
                :if={!script.sudo and (script.params != [] or script.optional_params != [])}
                id={"script-inline-#{script.file}"}
                phx-change="update_inline_params"
                class="space-y-1.5 mt-1"
              >
                <input type="hidden" name="file" value={script.file} />
                <% configured = @project.params |> Enum.filter(&(&1.key in (script.params ++ script.optional_params))) |> Map.new(&{&1.key, &1.value}) %>
                <% inline = Map.get(@inline_params, script.file, %{}) %>
                <div :for={param_key <- script.params} class="flex items-center gap-2 min-w-0">
                  <span class="font-mono text-[11px] text-[#5c6b66] w-36 shrink-0 truncate">{param_key}</span>
                  <input
                    type="text"
                    name={"inline[#{param_key}]"}
                    value={Map.get(inline, param_key, "")}
                    placeholder={Map.get(configured, param_key) || "required"}
                    class={[
                      "min-w-0 flex-1 bg-[#0D1113] font-mono text-xs px-2 py-1 rounded-[4px] focus:outline-none",
                      if(Map.has_key?(configured, param_key),
                        do: "border border-[#242D31] focus:border-[#3C5934] placeholder-[#86948F]",
                        else: "border border-[#E0A458]/60 focus:border-[#E0A458] placeholder-[#E0A458]/60"
                      )
                    ]}
                  />
                </div>
                <div :for={param_key <- script.optional_params} class="flex items-center gap-2 min-w-0">
                  <span class="font-mono text-[11px] text-[#5c6b66] w-36 shrink-0 truncate">{param_key}</span>
                  <input
                    type="text"
                    name={"inline[#{param_key}]"}
                    value={Map.get(inline, param_key, "")}
                    placeholder={Map.get(configured, param_key) || "optional"}
                    class="min-w-0 flex-1 bg-[#0D1113] border border-[#242D31] font-mono text-xs px-2 py-1 rounded-[4px] focus:border-[#3C5934] focus:outline-none placeholder-[#86948F]"
                  />
                </div>
                <% inline = Map.get(@inline_params, script.file, %{}) %>
                <% can_run = Enum.all?(script.params, fn k -> Map.has_key?(configured, k) or String.trim(Map.get(inline, k, "")) != "" end) %>
                <div class="flex justify-end pt-1">
                  <button
                    type="button"
                    phx-click="run_script"
                    phx-value-file={script.file}
                    disabled={not can_run}
                    class="px-3 py-1.5 rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#E6ECE9] hover:bg-[#1A2226] disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                  >
                    Run
                  </button>
                </div>
              </form>
            </div>
          </div>

          <div :for={{runner_id, runner} <- @running_scripts} class="mt-4 rounded-[4px] border border-[#242D31] overflow-hidden">
            <div class="flex items-center justify-between px-3 py-2 bg-[#151B1E] border-b border-[#242D31]">
              <span class="font-mono text-[11.5px] text-[#86948F]">{runner.name}</span>
              <div class="flex items-center gap-2">
                <span class={[
                  "font-mono text-[11px]",
                  cond do
                    runner.status == :running -> "text-[#86948F] animate-pulse"
                    runner.status == :done -> "text-[#7FB069]"
                    true -> "text-[#E0A458]"
                  end
                ]}>
                  {runner.status}
                </span>
                <button phx-click="clear_script_output" phx-value-runner_id={runner_id} class="font-mono text-[#86948F] hover:text-[#E6ECE9] cursor-pointer">
                  ×
                </button>
              </div>
            </div>
            <div
              id={"script-output-#{runner_id}"}
              phx-hook="ScrollBottom"
              class="p-3 bg-[#0D1113] font-mono text-[11.5px] text-[#B9C4BF] max-h-64 overflow-y-auto whitespace-pre-wrap select-text"
            >{runner.output |> Enum.join("") |> clean_output()}</div>
          </div>
        </div>

        <p :if={@scripts == []} class="text-[#86948F] text-sm">
          No scripts discovered under <code class="font-mono">source/scripts/</code>.
        </p>
      </main>
    </div>
    """
  end
end
