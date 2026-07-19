defmodule Skills.Module do
  @moduledoc """
  The `SapoKit.Module` implementation for the skills module — see
  `Skills` for the actual logic.
  """
  use SapoKit.Module

  @impl true
  def id, do: :skills

  @impl true
  def title, do: "Skills"

  @impl true
  def icon, do: "hero-academic-cap"

  # Own directory for custom skill folders (`custom/<name>/SKILL.md` +
  # supporting files) — kept live in Claude via a standing symlink, see
  # `Skills.reconcile!/0`.
  @impl true
  def storage_paths, do: ["custom"]

  # Runs Skills.reconcile!/0 once at every app boot — Task's default
  # child_spec is `restart: :temporary`, so its normal exit isn't treated
  # as a supervision failure.
  @impl true
  def children(_config), do: [{Task, &Skills.reconcile!/0}]

  @impl true
  def ui_routes do
    [%{path: "/skills", live_view: SkillsWeb.Live.Index, action: :index}]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/skills", controller: SkillsWeb.Api.SkillsController, action: :index},
      %{verb: :get, path: "/skills/:id", controller: SkillsWeb.Api.SkillsController, action: :show},
      %{
        verb: :post,
        path: "/skills/marketplace",
        controller: SkillsWeb.Api.SkillsController,
        action: :create_marketplace
      },
      %{
        verb: :post,
        path: "/skills/custom",
        controller: SkillsWeb.Api.SkillsController,
        action: :create_custom
      },
      %{verb: :delete, path: "/skills/:id", controller: SkillsWeb.Api.SkillsController, action: :delete}
    ]
  end

  @impl true
  def ai_context do
    """
    Skills manages which Claude Code skills/plugins are installed —
    #{length(Skills.list_skills())} tracked right now. Two kinds:
    marketplace plugins (installed via `claude plugin`) and custom skills
    (folders under this module's own storage `custom/<name>/`, live in
    Claude via a standing `~/.claude/skills` symlink). Once this module is
    enabled it fully owns marketplace plugin enablement — not the
    `services.sapohub.assistant.claudeDefaults.user` Nix option.
    Use `sapo skills list|show|add-marketplace|register|delete` or the
    /api/skills endpoints.
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    Custom Claude Code skills are authored by writing directly into this
    module's storage `custom/<name>/` folder (SKILL.md + any supporting
    files, one folder per skill) — then register it with
    `sapo skills register <name>` so it's tracked (the folder must already
    exist first). Add a marketplace skill with `sapo skills
    add-marketplace <name> [--marketplace <name>]` (default marketplace:
    claude-plugins-official). Remove either kind with `sapo skills delete
    <id>` (see `sapo skills list` for ids) — deletion is permanent, it
    won't come back from Nix defaults.
    """
  end
end
