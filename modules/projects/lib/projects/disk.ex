defmodule Projects.Disk do
  @moduledoc """
  Filesystem layout for cloned projects, ported from v1's `DiskManager`.

  v1 kept projects under a configurable `~/projects` base directory. In v2
  that base is simply this module's opted-in storage directory
  (`SapoKit.Storage.dir(:projects)`) — no separate config knob needed, and
  it's automatically included in snapshots/the storage file API like any
  other module's storage.
  """

  @doc "Base directory all project directories live under."
  def projects_base, do: SapoKit.Storage.dir(:projects)

  @doc "Full path to a project's root directory: `<projects_base>/<name>`."
  def project_root(name), do: Path.join(projects_base(), name)

  @doc "`source/` dir inside the project root — where the git repo is cloned."
  def source_path(name), do: Path.join(project_root(name), "source")

  @doc "`workspace/` dir inside the project root — for plans/notes, not committed."
  def workspace_path(name), do: Path.join(project_root(name), "workspace")

  @doc "CLAUDE.md path inside the project root."
  def claude_md_path(name), do: Path.join(project_root(name), "CLAUDE.md")

  @doc "Path to the shared script-headers reference guide."
  def scripts_guide_path, do: Path.join(projects_base(), "sapohub-scripts.md")

  @doc "Deletes a project's directory tree from disk."
  def delete_project(name) do
    case File.rm_rf(project_root(name)) do
      {:ok, _} -> :ok
      {:error, reason, path} -> {:error, "Failed to delete #{path}: #{reason}"}
    end
  end

  @doc "(Re)writes the scripts guide into the shared projects base directory."
  def sync_guide, do: File.write(scripts_guide_path(), scripts_guide())

  @doc """
  Creates `source/` and `workspace/` for a fresh project and writes its
  CLAUDE.md + the shared scripts guide. Returns `{:ok, root}` or `{:error, reason}`.
  """
  def setup_project(name) do
    root = project_root(name)

    with :ok <- File.mkdir_p(source_path(name)),
         :ok <- File.mkdir_p(workspace_path(name)),
         :ok <- File.write(scripts_guide_path(), scripts_guide()),
         :ok <- File.write(claude_md_path(name), claude_md_template(name)) do
      {:ok, root}
    end
  end

  defp claude_md_template(name) do
    """
    # #{name}

    Source code is in `source/`, workspace files (plans, notes) are in `workspace/`.

    ## SapoHub Scripts

    Runnable scripts are discovered from `source/scripts/*.sh` and exposed in the
    SapoHub Projects module. See the full script header reference at:
    #{scripts_guide_path()}
    """
  end

  defp scripts_guide do
    """
    # SapoHub Script Headers Reference

    Scripts placed in `source/scripts/*.sh` are automatically discovered and exposed
    for this project. A script is only visible if it has a `SAPO_SCRIPT_NAME` header.

    ## Headers

    ```sh
    # SAPO_SCRIPT_NAME: Human-readable name    (required — makes script visible)
    # SAPO_SCRIPT_PARAM: param_name            (required parameter)
    # SAPO_SCRIPT_PARAM_OPTIONAL: param_name   (optional parameter)
    # SAPO_SCRIPT_SUDO: true                   (script requires root — see note below)
    # SAPO_SCRIPT_SYNC: true                   (sync repo before running — aborts on failure)
    #                                           Use for: deploys, migrations, anything that
    #                                           ships code to production. The script must run
    #                                           against the latest committed code.
    #                                           Skip for: quick utilities, data queries,
    #                                           one-off tasks that don't depend on repo state.
    ```

    ## Parameters

    Parameters are passed to the script as environment variables.

    - **Required** (`SAPO_SCRIPT_PARAM`): must have a value configured in project
      Settings, or filled in inline on the project page before running. The Run
      button is disabled until all required params are provided.
    - **Optional** (`SAPO_SCRIPT_PARAM_OPTIONAL`): shown as inputs when running but
      do not block the Run button. If left empty they are not passed to the script.

    ## Sudo scripts

    `SAPO_SCRIPT_SUDO: true` scripts are discovered and listed, but **cannot be run
    from the Projects module** in this version of SapoHub — there is no interactive
    root-escalation mechanism (unlike v1's password-gated sudo runner). Run them
    manually on the host if needed.
    """
  end
end
