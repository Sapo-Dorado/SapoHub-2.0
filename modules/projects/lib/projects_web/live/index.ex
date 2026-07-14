defmodule ProjectsWeb.Live.Index do
  @moduledoc """
  Projects list page: name + last-pulled-at per project, drag-reorderable
  (via the module's `ProjectSortable` hook), a create-project modal
  (name + github URL), and a pending "Setting up project…" row while the
  clone runs. Ported from v1's `ProjectsLive`.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("projects:list")

    {:ok,
     socket
     |> assign(
       show_form: false,
       reordering: false,
       form_errors: %{},
       name_value: "",
       github_url_value: "",
       creating: false,
       create_error: nil
     )
     |> load()}
  end

  defp load(socket), do: assign(socket, projects: Projects.list_projects())

  @impl true
  def handle_event("toggle_reorder", _, socket) do
    {:noreply, assign(socket, reordering: !socket.assigns.reordering)}
  end

  def handle_event("reorder_projects", %{"ids" => ids}, socket) do
    Projects.reorder_projects(ids)
    {:noreply, load(socket)}
  end

  def handle_event("show_form", _, socket) do
    {:noreply, assign(socket, show_form: true, create_error: nil, form_errors: %{}, name_value: "", github_url_value: "")}
  end

  def handle_event("hide_form", _, socket) do
    {:noreply, assign(socket, show_form: false)}
  end

  def handle_event("create_project", %{"project" => params}, socket) do
    case Projects.create_project(%{"name" => params["name"], "github_url" => params["github_url"]}) do
      {:ok, project} ->
        socket = assign(socket, creating: true, show_form: false, create_error: nil, projects: Projects.list_projects())
        send(self(), {:setup_and_clone, project})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form_errors: format_errors(changeset),
           create_error: "Please fix the errors below.",
           name_value: params["name"] || "",
           github_url_value: params["github_url"] || ""
         )}
    end
  end

  @impl true
  def handle_info({:setup_and_clone, project}, socket) do
    project = Projects.get_project!(project.id)

    with {:ok, _root} <- Projects.Disk.setup_project(project.name),
         {:ok, _output} <- Projects.Git.clone(project.name, project.github_url),
         {:ok, _} <- Projects.Git.initialize_if_empty(project.name),
         {:ok, updated} <- Projects.update_project(project, %{last_pulled_at: DateTime.utc_now() |> DateTime.truncate(:second)}) do
      {:noreply, push_navigate(socket, to: "/projects/#{updated.id}")}
    else
      {:error, reason} ->
        Projects.delete_project(project)

        {:noreply,
         assign(socket, creating: false, projects: Projects.list_projects(), create_error: "Setup failed: #{inspect(reason)}")}
    end
  end

  def handle_info(:reordered, socket), do: {:noreply, load(socket)}
  def handle_info({:created, _}, socket), do: {:noreply, load(socket)}
  def handle_info({:deleted, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
  end

  defp relative_pulled(nil), do: "never pulled"
  defp relative_pulled(%DateTime{} = dt), do: "last pulled #{dt |> DateTime.to_naive() |> NaiveDateTime.to_string()}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="projects" items={@statusline} />

      <main class="max-w-[720px] mx-auto px-4 py-6 space-y-5">
        <div class="flex items-center justify-between">
          <h1 class="font-mono text-[13.5px] font-semibold">projects</h1>
          <div class="flex items-center gap-2">
            <button
              :if={length(@projects) > 1}
              phx-click="toggle_reorder"
              class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
            >
              {if @reordering, do: "done", else: "reorder"}
            </button>
            <button
              :if={!@reordering}
              phx-click="show_form"
              class="px-3 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[11.5px] font-semibold cursor-pointer"
            >
              + new project
            </button>
          </div>
        </div>

        <div :if={@create_error} class="p-3 rounded-[4px] border border-[#E0A458] text-[#E0A458] text-xs font-mono">
          {@create_error}
        </div>

        <div :if={@creating} class="p-4 rounded-[4px] border border-[#242D31] text-[#86948F] text-sm font-mono animate-pulse">
          Setting up project…
        </div>

        <ul id="projects-list" phx-hook="ProjectSortable" data-sorting={"#{@reordering}"} class="space-y-2">
          <li
            :for={project <- @projects}
            id={"project-#{project.id}"}
            data-id={project.id}
            class="flex items-stretch rounded-[4px] border border-[#242D31] bg-[#151B1E] hover:bg-[#1A2226] transition-colors"
          >
            <div class={[
              "drag-handle flex items-center px-2 cursor-grab text-[#3C5934] hover:text-[#86948F] select-none shrink-0 font-mono text-[13px] transition-all",
              if(@reordering, do: "opacity-100 w-auto", else: "opacity-0 w-0 px-0 overflow-hidden")
            ]}>
              ⠿
            </div>
            <.link
              navigate={"/projects/#{project.id}"}
              class="flex-1 min-w-0 px-4 py-3.5"
              style={if @reordering, do: "pointer-events: none;", else: ""}
            >
              <div class="font-mono text-sm font-semibold truncate">{project.name}</div>
              <div class="font-mono text-[11.5px] text-[#86948F] mt-0.5">{relative_pulled(project.last_pulled_at)}</div>
            </.link>
          </li>
        </ul>

        <p :if={@projects == [] and !@creating} class="text-center text-[#86948F] text-sm py-8">
          No projects yet. Add one above.
        </p>
      </main>

      <div
        :if={@show_form}
        id="new-project-modal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
        phx-window-keydown="hide_form"
        phx-key="escape"
      >
        <div class="absolute inset-0" phx-click="hide_form"></div>
        <div class="relative w-full max-w-[420px] rounded-[4px] bg-[#151B1E] border border-[#242D31] p-5">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-4">
            new project
          </div>
          <form phx-submit="create_project" class="space-y-3">
            <div>
              <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">name</label>
              <input
                type="text"
                name="project[name]"
                value={@name_value}
                placeholder="my-project"
                autofocus
                class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
              />
              <p :if={error = @form_errors[:name]} class="text-xs font-mono text-[#E0A458] mt-1">{List.first(error)}</p>
              <p class="text-[11px] font-mono text-[#86948F] mt-1">Lowercase letters, numbers, hyphens only</p>
            </div>
            <div>
              <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">github url</label>
              <input
                type="text"
                name="project[github_url]"
                value={@github_url_value}
                placeholder="https://github.com/user/repo"
                class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
              />
              <p :if={error = @form_errors[:github_url]} class="text-xs font-mono text-[#E0A458] mt-1">{List.first(error)}</p>
            </div>
            <div class="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="hide_form"
                class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold cursor-pointer"
              >
                Create
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
