defmodule Projects do
  @moduledoc """
  Context for the Projects module: GitHub-repo-backed project directories,
  discoverable/runnable scripts, and per-project script parameters. Ported
  from v1's `SapoHub.Projects` + `ProjectsLive`/`ProjectDetailLive`/
  `ProjectSettingsLive` business logic.

  Sudo-script execution is intentionally NOT implemented — see
  `Projects.ScriptCommand` and the migration report for why.
  """

  import Ecto.Query

  alias Projects.{Disk, Git, Project, ProjectParam, ScriptParser}
  alias SapoKit.Repo

  # ── Projects ────────────────────────────────────────────────────────────

  def list_projects do
    Project
    |> order_by([p], asc: p.position, asc: p.name)
    |> preload(:params)
    |> Repo.all()
  end

  def get_project!(id) do
    Project
    |> preload(:params)
    |> Repo.get!(id)
  end

  def new_project_changeset, do: Project.changeset(%Project{}, %{})

  def create_project(attrs), do: %Project{} |> Project.changeset(attrs) |> Repo.insert()

  def update_project(%Project{} = project, attrs) do
    case project |> Project.changeset(attrs) |> Repo.update() do
      {:ok, updated} -> {:ok, Repo.preload(updated, :params, force: true)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def reorder_projects(ordered_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ordered_ids
    |> Enum.with_index()
    |> Enum.each(fn {id, position} ->
      from(p in Project, where: p.id == ^id)
      |> Repo.update_all(set: [position: position, updated_at: now])
    end)

    broadcast(:reordered)
  end

  @doc """
  Full project setup: DB row + directory scaffolding + git clone (+ empty-repo
  bootstrap). Rolls back the DB row on any setup/clone failure, same as v1.
  Returns `{:ok, project}` or `{:error, reason}`.
  """
  def create_and_setup(attrs) do
    case create_project(attrs) do
      {:ok, project} ->
        with {:ok, _root} <- Disk.setup_project(project.name),
             {:ok, _output} <- Git.clone(project.name, project.github_url),
             {:ok, _} <- Git.initialize_if_empty(project.name),
             {:ok, updated} <- mark_pulled(project) do
          broadcast(:created, updated)
          {:ok, updated}
        else
          {:error, reason} ->
            delete_project(project)
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Pulls the latest commits and updates `last_pulled_at`. Returns `{:ok, project}` or `{:error, reason}`."
  def pull_project(%Project{} = project) do
    case Git.pull(project.name) do
      {:ok, _output} -> mark_pulled(project)
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_pulled(%Project{} = project) do
    update_project(project, %{last_pulled_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  @doc """
  Deletes a project's DB row and its on-disk directory, after confirming it's
  safe to do so (no uncommitted changes / unpushed commits). Returns `:ok` or
  `{:error, reason}`.
  """
  def delete_project_safely(%Project{} = project) do
    case Git.safe_to_delete?(project.name) do
      {:ok, :safe} ->
        {:ok, _} = delete_project(project)
        Disk.delete_project(project.name)
        broadcast(:deleted, project)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Params ──────────────────────────────────────────────────────────────

  def list_params(project_id) do
    ProjectParam
    |> where([pp], pp.project_id == ^project_id)
    |> order_by([pp], asc: pp.key)
    |> Repo.all()
  end

  def upsert_param(project_id, key, value) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert(
      %ProjectParam{project_id: project_id, key: key, value: value, inserted_at: now, updated_at: now},
      on_conflict: [set: [value: value, updated_at: now]],
      conflict_target: [:project_id, :key],
      returning: true
    )
  end

  def delete_param(project_id, key) do
    ProjectParam
    |> where([pp], pp.project_id == ^project_id and pp.key == ^key)
    |> Repo.delete_all()
  end

  # ── Scripts ─────────────────────────────────────────────────────────────

  def list_scripts(%Project{} = project), do: ScriptParser.parse_scripts(project.name)

  @doc "Non-sudo scripts only — used for the CLI/API surface (mirrors v1's `scripts` API, which also filters sudo out)."
  def list_runnable_scripts(%Project{} = project) do
    project |> list_scripts() |> Enum.reject(& &1.sudo)
  end

  @doc """
  Starts a live-streaming run of a non-sudo script (used by the LiveView).
  If the script is `sync: true`, pulls first (aborting on pull failure).
  Returns `{:ok, runner_id, project}` (project reloaded if a sync-pull
  happened) or `{:error, reason}`.
  """
  def run_script_live(%Project{} = project, script, param_values) do
    with {:ok, project} <- maybe_sync(project, script) do
      script_with_params = Map.put(script, :params_values, param_values)

      case Projects.Runner.start(project.id, script_with_params, Disk.project_root(project.name)) do
        {:ok, runner_id, _pid} -> {:ok, runner_id, project}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Runs a non-sudo script and blocks until completion or `timeout_ms`,
  capturing combined output — used by the API/CLI (mirrors v1's blocking
  `run_script` controller action). Sudo scripts are rejected.
  """
  def run_script_blocking(project, script, param_values, timeout_ms \\ 120_000)

  def run_script_blocking(%Project{}, %{sudo: true}, _param_values, _timeout_ms) do
    {:error, :sudo_unsupported}
  end

  def run_script_blocking(%Project{} = project, script, param_values, timeout_ms) do
    script_with_params = Map.put(script, :params_values, param_values)
    project_root = Disk.project_root(project.name)

    case Projects.ScriptCommand.build(script_with_params, project_root) do
      {:ok, {cmd, args, env, cwd}} ->
        task =
          Task.async(fn ->
            start = System.monotonic_time(:millisecond)
            {output, exit_code} = System.cmd(cmd, args, env: env, cd: cwd, stderr_to_stdout: true)
            {output, exit_code, System.monotonic_time(:millisecond) - start}
          end)

        case Task.yield(task, timeout_ms) || Task.shutdown(task) do
          {:ok, {output, exit_code, duration_ms}} -> {:ok, %{output: output, exit_code: exit_code, duration_ms: duration_ms}}
          nil -> {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_sync(%Project{} = project, %{sync: true}), do: pull_project(project)
  defp maybe_sync(%Project{} = project, _script), do: {:ok, project}

  # ── PubSub ──────────────────────────────────────────────────────────────

  defp broadcast(event), do: SapoKit.PubSub.broadcast("projects:list", event)
  defp broadcast(event, payload), do: SapoKit.PubSub.broadcast("projects:list", {event, payload})
end
