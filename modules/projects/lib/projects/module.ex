defmodule Projects.Module do
  @moduledoc """
  `SapoKit.Module` implementation for Projects — GitHub-repo-backed project
  directories with discoverable/runnable scripts, ported from v1's biggest
  utility.

  ## Known gap: sudo scripts

  v1 discovered scripts with a `SAPO_SCRIPT_SUDO: true` header and let a
  human run them from the project page after confirming a local app-user
  password, shelling out through `/run/wrappers/bin/sudo`. v2 has no
  auth/user system at all, and its only root-escalation path is a single,
  Nix-fixed `sapohub-deploy` sudoers grant — deliberately narrow, and
  verified by the release VM test. Reproducing v1's sudo-script runner
  would mean either inventing a new auth system in core AND widening that
  sudoers grant to arbitrary git-pulled scripts (undermining the "single
  fixed command" guarantee), which is a real security-posture decision,
  not a small mapping detail. This module still discovers and *displays*
  sudo scripts (so nothing is silently hidden), but does not run them —
  see the migration report for the explicit open question raised to the
  user.
  """
  use SapoKit.Module

  @impl true
  def id, do: :projects

  @impl true
  def title, do: "Projects"

  @impl true
  def icon, do: "hero-code-bracket-square"

  @impl true
  def ui_routes do
    [
      %{path: "/projects", live_view: ProjectsWeb.Live.Index, action: :index},
      %{path: "/projects/:id", live_view: ProjectsWeb.Live.Show, action: :show},
      %{path: "/projects/:id/settings", live_view: ProjectsWeb.Live.Settings, action: :show}
    ]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/projects", controller: ProjectsWeb.Api.ProjectsController, action: :index},
      %{verb: :post, path: "/projects", controller: ProjectsWeb.Api.ProjectsController, action: :create},
      %{verb: :get, path: "/projects/:id", controller: ProjectsWeb.Api.ProjectsController, action: :show},
      %{verb: :delete, path: "/projects/:id", controller: ProjectsWeb.Api.ProjectsController, action: :delete},
      %{verb: :get, path: "/projects/:id/scripts", controller: ProjectsWeb.Api.ScriptsController, action: :index},
      %{verb: :post, path: "/projects/:id/scripts/run", controller: ProjectsWeb.Api.ScriptsController, action: :run},
      %{verb: :get, path: "/projects/:id/params", controller: ProjectsWeb.Api.ParamsController, action: :index},
      %{verb: :put, path: "/projects/:id/params/:key", controller: ProjectsWeb.Api.ParamsController, action: :upsert},
      %{verb: :delete, path: "/projects/:id/params/:key", controller: ProjectsWeb.Api.ParamsController, action: :delete}
    ]
  end

  @impl true
  def storage_paths, do: ["."]

  @impl true
  def children(_config), do: [Projects.RunnerSupervisor]

  @impl true
  def ai_context do
    projects = Projects.list_projects()
    count = length(projects)

    summary =
      if count == 0 do
        "(none yet)"
      else
        Enum.map_join(projects, "\n", fn p ->
          pulled = if p.last_pulled_at, do: DateTime.to_iso8601(p.last_pulled_at), else: "never"
          "- #{p.name} (id: #{p.id}) — #{p.github_url} — last pulled: #{pulled}"
        end)
      end

    """
    Projects manages GitHub-repo-backed project directories (#{count} total):
    #{summary}

    Each project clones its `github_url` into a dedicated `source/` directory
    and discovers runnable scripts from `source/scripts/*.sh` (headers:
    `SAPO_SCRIPT_NAME`/`SAPO_SCRIPT_PARAM`/`SAPO_SCRIPT_PARAM_OPTIONAL`/
    `SAPO_SCRIPT_SYNC`; see a project's `GET /api/projects/:id/scripts`).
    Use `sapo projects ...` / `sapo scripts ...` or the /api/projects
    endpoints. NOTE: scripts with `SAPO_SCRIPT_SUDO: true` are listed but
    CANNOT be run via the API, CLI, or UI in this version — do not attempt
    to work around this by running them directly in the shell either.
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    Project source trees live under the Projects module (`sapo projects`,
    `sapo scripts`). Sudo-flagged scripts are intentionally not runnable
    through any Projects interface — don't try to execute them via sudo
    in the shell as a workaround.
    """
  end
end
