defmodule SkillsWeb.Live.Index do
  @moduledoc """
  Skills page: view-only list of tracked skills (marketplace plugins +
  custom folders), each with a read-only detail viewer and a two-step
  delete confirmation. Adding/registering a skill is CLI/assistant-only
  (`sapo skills add-marketplace|register` — see `Skills.Module`'s
  `assistant_system_prompt/0`), matching this module's spec; deletion is
  the one mutation the UI itself supports.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(confirm_delete: nil, viewer: nil) |> load()}
  end

  defp load(socket) do
    skills = Skills.list_skills()

    assign(socket,
      skills: skills,
      marketplace_skills: Enum.filter(skills, &(&1.kind == "marketplace")),
      custom_skills: Enum.filter(skills, &(&1.kind == "custom"))
    )
  end

  # ── Viewer ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("view", %{"id" => id}, socket) do
    skill = Skills.get_skill!(id)

    content =
      case Skills.skill_detail(skill) do
        {:ok, content} -> content
        {:error, reason} -> "(could not load detail: #{inspect(reason)})"
      end

    {:noreply, assign(socket, viewer: %{skill: skill, content: content})}
  end

  def handle_event("close_viewer", _, socket) do
    {:noreply, assign(socket, viewer: nil)}
  end

  # ── Delete (two-step confirm, no native dialogs) ────────────────────────

  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirm_delete: Skills.get_skill!(id))}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete", _, socket) do
    Skills.delete_skill(socket.assigns.confirm_delete)
    {:noreply, socket |> assign(confirm_delete: nil) |> load()}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp skill_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-center gap-2.5 font-mono text-[10.5px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
        <span>{@title}</span>
        <span class="h-px flex-1 bg-[#242D31]"></span>
      </div>

      <div class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] overflow-hidden">
        <div :for={skill <- @skills} class="flex flex-col gap-1 px-3 py-2.5 bg-[#151B1E] font-mono text-[12px]">
          <div class="flex items-center gap-3">
            <button
              :if={skill.kind == "custom"}
              phx-click="view"
              phx-value-id={skill.id}
              class="flex-1 min-w-0 text-left truncate text-[#E6ECE9] hover:text-[#7FB069]"
              title={skill.name}
            >{skill.name}</button>
            <span
              :if={skill.kind != "custom"}
              class="flex-1 min-w-0 truncate text-[#E6ECE9]"
              title={skill.name}
            >{skill.name}</span>
            <button
              phx-click="request_delete"
              phx-value-id={skill.id}
              class="shrink-0 text-[#86948F] hover:text-[#E05C5C]"
            >✕</button>
          </div>
          <span :if={skill.marketplace} class="text-[#86948F] text-[10.5px] truncate">@{skill.marketplace}</span>
        </div>

        <p :if={@skills == []} class="px-3 py-4 text-center font-mono text-[11.5px] text-[#86948F]">
          {@empty}
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline
        crumb="skills"
        items={@statusline}
        right={"#{length(@skills)} skill#{if length(@skills) == 1, do: "", else: "s"}"}
      />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[720px] mx-auto px-4 py-8 space-y-6">
        <div class="flex items-center gap-2.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
          <span>Skills</span>
          <span class="h-px flex-1 bg-[#242D31]"></span>
        </div>

        <p class="font-mono text-[11.5px] text-[#86948F]">
          Add or remove skills with <span class="text-[#E6ECE9]">sapo skills</span> —
          see <span class="text-[#E6ECE9]">sapo skills help</span>.
        </p>

        <p :if={@skills == []} class="px-3 py-6 text-center font-mono text-[12px] text-[#86948F] rounded-[4px] border border-[#242D31]">
          No skills tracked yet.
        </p>

        <.skill_section :if={@skills != []} title="Marketplace" skills={@marketplace_skills} empty="No marketplace skills." />
        <.skill_section :if={@skills != []} title="Custom" skills={@custom_skills} empty="No custom skills." />
      </main>
    </div>

    <%!-- Delete confirmation modal --%>
    <div
      :if={@confirm_delete}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="cancel_delete"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60" phx-click="cancel_delete"></div>
      <div class="relative rounded-[4px] bg-[#151B1E] border border-[#242D31] max-w-sm w-full p-6 space-y-4">
        <p class="font-mono text-sm text-[#E6ECE9]">
          Delete skill <span class="text-[#7FB069]">"{@confirm_delete.name}"</span>?
          <span class="text-[#86948F] text-xs block mt-1">
            {if @confirm_delete.kind == "custom",
              do: "Its storage folder will be removed too.",
              else: "It will be uninstalled from Claude."}
          </span>
        </p>
        <div class="flex gap-3">
          <button
            phx-click="delete"
            class="px-4 py-2 rounded-[4px] font-mono text-xs border border-[#E05C5C] text-[#E05C5C] hover:bg-[#E05C5C] hover:text-[#0D1113] transition-colors"
          >delete</button>
          <button
            phx-click="cancel_delete"
            class="px-4 py-2 rounded-[4px] font-mono text-xs border border-[#242D31] text-[#86948F] hover:text-[#E6ECE9] transition-colors"
          >cancel</button>
        </div>
      </div>
    </div>

    <%!-- Detail viewer modal --%>
    <div
      :if={@viewer}
      class="fixed inset-0 z-50 flex flex-col"
      phx-window-keydown="close_viewer"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/90" phx-click="close_viewer"></div>
      <div class="relative flex items-center justify-between px-4 py-3 font-mono text-[11.5px] text-[#86948F] shrink-0">
        <span class="truncate">{@viewer.skill.name}</span>
        <button phx-click="close_viewer" class="hover:text-[#E6ECE9]">✕ close</button>
      </div>
      <div class="relative flex-1 overflow-hidden p-4 flex">
        <pre
          class="w-full h-full max-w-[960px] mx-auto overflow-auto rounded-[4px] border border-[#242D31] bg-[#151B1E] text-[#E6ECE9] text-[12px] font-mono p-4 whitespace-pre-wrap break-words"
        >{@viewer.content}</pre>
      </div>
    </div>
    """
  end
end
