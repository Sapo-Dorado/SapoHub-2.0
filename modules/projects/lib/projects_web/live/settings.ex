defmodule ProjectsWeb.Live.Settings do
  @moduledoc """
  Project settings page: github_url edit, script-parameter values
  (required/optional keys auto-discovered from all scripts), and a
  danger zone delete (blocked with a reason if unsafe). Ported from v1's
  `ProjectSettingsLive`.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)
    scripts = Projects.list_scripts(project)

    required_params = scripts |> Enum.flat_map(& &1.params) |> Enum.uniq() |> Enum.sort()

    optional_params =
      scripts
      |> Enum.flat_map(& &1.optional_params)
      |> Enum.uniq()
      |> Enum.sort()
      |> Kernel.--(required_params)

    {:ok,
     assign(socket,
       project: project,
       required_params: required_params,
       optional_params: optional_params,
       github_saved: false,
       saved_params: MapSet.new(),
       delete_confirm: false,
       delete_error: nil
     )}
  end

  @impl true
  def handle_event("save_github_url", %{"github_url" => url}, socket) do
    case Projects.update_project(socket.assigns.project, %{github_url: url}) do
      {:ok, project} -> {:noreply, assign(socket, project: project, github_saved: true)}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Failed to update URL")}
    end
  end

  def handle_event("save_param", %{"key" => key, "value" => value}, socket) do
    project = socket.assigns.project
    trimmed = String.trim(value)

    result =
      if trimmed == "" do
        Projects.delete_param(project.id, key)
        :cleared
      else
        Projects.upsert_param(project.id, key, trimmed)
      end

    case result do
      :cleared ->
        updated = Projects.get_project!(project.id)
        Process.send_after(self(), {:clear_saved_param, key}, 2000)
        {:noreply, assign(socket, project: updated, saved_params: MapSet.put(socket.assigns.saved_params, key))}

      {:ok, _} ->
        updated = Projects.get_project!(project.id)
        Process.send_after(self(), {:clear_saved_param, key}, 2000)
        {:noreply, assign(socket, project: updated, saved_params: MapSet.put(socket.assigns.saved_params, key))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
    end
  end

  def handle_event("confirm_delete", _, socket), do: {:noreply, assign(socket, delete_confirm: true)}

  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, delete_confirm: false, delete_error: nil)}

  def handle_event("delete_project", _, socket) do
    project = socket.assigns.project

    case Projects.delete_project_safely(project) do
      :ok -> {:noreply, push_navigate(socket, to: "/projects")}
      {:error, reason} -> {:noreply, assign(socket, delete_error: reason)}
    end
  end

  @impl true
  def handle_info({:clear_saved_param, key}, socket) do
    {:noreply, assign(socket, saved_params: MapSet.delete(socket.assigns.saved_params, key))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb={"projects / #{@project.name} / settings"} items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-7">
        <div>
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-3">
            repository
          </div>
          <form phx-submit="save_github_url" class="flex gap-2">
            <input
              type="text"
              name="github_url"
              value={@project.github_url}
              class="flex-1 min-w-0 bg-[#0D1113] border border-[#242D31] text-[#E6ECE9] font-mono text-sm px-3 py-2 rounded-[4px] focus:border-[#7FB069] focus:outline-none"
            />
            <button
              type="submit"
              class="shrink-0 px-3 py-2 rounded-[4px] border border-[#242D31] text-xs font-mono text-[#86948F] hover:text-[#E6ECE9] hover:bg-[#1A2226] cursor-pointer"
            >
              Save
            </button>
          </form>
          <p :if={@github_saved} class="text-xs font-mono text-[#7FB069] mt-1.5">Saved.</p>
        </div>

        <div>
          <div class="flex items-baseline justify-between mb-3">
            <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
              parameters
            </div>
            <span class="text-[10px] font-mono text-[#5c6b66]">from source/scripts/</span>
          </div>

          <p :if={@required_params == [] and @optional_params == []} class="text-xs font-mono text-[#5c6b66]">
            No parameters discovered.
          </p>

          <div :if={@required_params != [] or @optional_params != []} class="divide-y divide-[#242D31]">
            <div :for={param_key <- @required_params} class="py-3">
              <.param_form
                param_key={param_key}
                required?={true}
                current={Enum.find(@project.params, &(&1.key == param_key))}
                saved?={MapSet.member?(@saved_params, param_key)}
              />
            </div>
            <div :for={param_key <- @optional_params} class="py-3">
              <.param_form
                param_key={param_key}
                required?={false}
                current={Enum.find(@project.params, &(&1.key == param_key))}
                saved?={MapSet.member?(@saved_params, param_key)}
              />
            </div>
          </div>
        </div>

        <div class="border-t border-[#242D31] pt-6">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-4">
            danger zone
          </div>
          <button
            :if={!@delete_confirm}
            phx-click="confirm_delete"
            class="px-3 py-2 rounded-[4px] border border-[#E0A458]/50 text-xs font-mono text-[#E0A458] hover:border-[#E0A458] hover:bg-[#E0A458]/5 cursor-pointer"
          >
            Delete Project
          </button>
          <div :if={@delete_confirm} class="space-y-3">
            <p class="text-xs font-mono text-[#B9C4BF]">
              This will delete the project record and all files on disk.
            </p>
            <p :if={@delete_error} class="text-xs font-mono text-[#E0A458]">Blocked: {@delete_error}.</p>
            <div class="flex gap-2">
              <button
                phx-click="cancel_delete"
                class="px-3 py-2 rounded-[4px] border border-[#242D31] text-xs font-mono text-[#86948F] hover:text-[#E6ECE9] hover:bg-[#1A2226] cursor-pointer"
              >
                Cancel
              </button>
              <button
                phx-click="delete_project"
                class="px-3 py-2 rounded-[4px] border border-[#E0A458] text-xs font-mono text-[#E0A458] hover:bg-[#E0A458]/10 cursor-pointer"
              >
                Confirm Delete
              </button>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  attr :param_key, :string, required: true
  attr :required?, :boolean, required: true
  attr :current, :map, default: nil
  attr :saved?, :boolean, default: false

  defp param_form(assigns) do
    ~H"""
    <form phx-submit="save_param">
      <input type="hidden" name="key" value={@param_key} />
      <div class="flex items-center justify-between mb-1.5">
        <span class="font-mono text-xs text-[#E6ECE9] truncate mr-2">{@param_key}</span>
        <span class="text-[10px] font-mono text-[#5c6b66] uppercase tracking-wider shrink-0">
          {if @required?, do: "required", else: "optional"}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <input
          type="text"
          name="value"
          value={if @current, do: @current.value, else: ""}
          placeholder="not set"
          class="flex-1 min-w-0 bg-[#0D1113] border border-[#242D31] text-[#E6ECE9] font-mono text-xs px-2 py-1.5 rounded-[4px] focus:border-[#7FB069] focus:outline-none placeholder-[#5c6b66]"
        />
        <button
          type="submit"
          class="shrink-0 px-2 py-1.5 rounded-[4px] border border-[#242D31] text-xs font-mono text-[#86948F] hover:text-[#E6ECE9] hover:bg-[#1A2226] cursor-pointer"
        >
          Save
        </button>
        <span :if={@saved?} class="text-xs font-mono text-[#7FB069]">Saved.</span>
      </div>
    </form>
    """
  end
end
