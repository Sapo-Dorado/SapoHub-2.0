defmodule SapoCore.Snapshot do
  @moduledoc """
  "Save All Data" snapshots.

  A snapshot is `snapshots/sapohub-<ts>.tar.gz` containing:

    * `db.sqlite3` — online SQLite backup via `VACUUM INTO`
    * `storage/<module_id>/…` — every opted-in module's storage dir
    * `manifest.json` — created_at, module list with versions, applied
      migration versions

  No per-module snapshot code exists anywhere: the DB file plus the storage
  dirs fully cover persistable module state.

  Restore happens ONLY at boot (`SapoCore.Release.maybe_restore/0`), before
  the app starts, from a staged archive — see `restore_from/3`.
  """

  require Logger

  alias SapoCore.Generated.Registry
  alias SapoCore.Repo
  alias SapoCore.Storage

  @manifest_version 1

  # ── Save ───────────────────────────────────────────────────────────────────

  @doc "Create a snapshot archive. Returns `{:ok, path}`."
  @spec save() :: {:ok, String.t()} | {:error, term()}
  def save do
    dir = snapshots_dir()
    File.mkdir_p!(dir)

    ts = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    archive = Path.join(dir, "sapohub-#{ts}.tar.gz")

    tmp = Path.join(System.tmp_dir!(), "sapohub-snapshot-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      # 1. Online SQLite backup. VACUUM INTO writes a consistent copy
      #    without blocking other readers/writers.
      db_copy = Path.join(tmp, "db.sqlite3")
      Repo.query!("VACUUM INTO ?1", [db_copy])

      # 2. Storage dirs of opted-in modules.
      storage_tmp = Path.join(tmp, "storage")
      File.mkdir_p!(storage_tmp)

      for mod <- Storage.storage_modules() do
        src = Storage.dir(mod.id())

        if File.dir?(src) do
          File.cp_r!(src, Path.join(storage_tmp, to_string(mod.id())))
        end
      end

      # 3. Manifest.
      File.write!(Path.join(tmp, "manifest.json"), Jason.encode!(manifest(), pretty: true))

      # 4. Pack.
      case System.cmd("tar", ["czf", archive, "-C", tmp, "."], stderr_to_stdout: true) do
        {_out, 0} ->
          Logger.info("snapshot saved: #{archive}")
          {:ok, archive}

        {out, code} ->
          File.rm(archive)
          {:error, {:tar_failed, code, out}}
      end
    after
      File.rm_rf!(tmp)
    end
  end

  @doc "Existing snapshots, newest first."
  @spec list() :: [
          %{name: String.t(), path: String.t(), size: non_neg_integer(), mtime: DateTime.t()}
        ]
  def list do
    dir = snapshots_dir()

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(
          &(String.starts_with?(&1, "sapohub-") and String.ends_with?(&1, ".tar.gz"))
        )
        |> Enum.map(fn name ->
          path = Path.join(dir, name)
          stat = File.stat!(path, time: :posix)
          %{name: name, path: path, size: stat.size, mtime: DateTime.from_unix!(stat.mtime)}
        end)
        |> Enum.sort_by(& &1.name, :desc)

      {:error, _} ->
        []
    end
  end

  @doc "Resolve a snapshot NAME (not a path) for download. Traversal-safe."
  @spec fetch(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def fetch(name) do
    if Path.basename(name) == name and String.ends_with?(name, ".tar.gz") do
      path = Path.join(snapshots_dir(), name)
      if File.regular?(path), do: {:ok, path}, else: {:error, :not_found}
    else
      {:error, :not_found}
    end
  end

  # ── Restore (boot-time only) ───────────────────────────────────────────────

  @doc """
  Restore `archive` into `db_path` and `storage_root`.

  Called by `SapoCore.Release.maybe_restore/0` BEFORE the app starts (both
  default to the configured live paths). Keeps `pre-restore-backup.sqlite3`
  next to the DB. Storage dirs present in the archive replace the module's
  dir; modules in the archive that are no longer enabled are skipped with a
  warning. Migrations run AFTER restore (boot order), upgrading the
  restored DB forward.
  """
  @spec restore_from(String.t(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, term()}
  def restore_from(archive, db_path \\ nil, storage_root \\ nil) do
    db_path = db_path || Application.fetch_env!(:sapo_core, SapoCore.Repo)[:database]
    storage_root = storage_root || Application.fetch_env!(:sapo_core, :storage_root)

    tmp = Path.join(System.tmp_dir!(), "sapohub-restore-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      with {_out, 0} <-
             System.cmd("tar", ["xzf", archive, "-C", tmp], stderr_to_stdout: true),
           {:ok, manifest} <- read_manifest(tmp) do
        Logger.info("restoring snapshot created at #{manifest["created_at"]}")

        # Keep a safety copy of the current DB, then swap.
        if File.exists?(db_path) do
          File.cp!(db_path, Path.join(Path.dirname(db_path), "pre-restore-backup.sqlite3"))
        end

        File.mkdir_p!(Path.dirname(db_path))
        File.cp!(Path.join(tmp, "db.sqlite3"), db_path)
        # Stale WAL/SHM files must not survive a DB swap.
        File.rm(db_path <> "-wal")
        File.rm(db_path <> "-shm")

        restore_storage(tmp, storage_root)
        :ok
      else
        {out, code} when is_integer(code) -> {:error, {:tar_failed, code, out}}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf!(tmp)
    end
  end

  defp restore_storage(tmp, storage_root) do
    storage_tmp = Path.join(tmp, "storage")
    enabled = Map.new(Storage.storage_modules(), &{to_string(&1.id()), &1.id()})

    for entry <- ls_or_empty(storage_tmp) do
      case Map.fetch(enabled, entry) do
        {:ok, module_id} ->
          target = storage_dir_for(module_id, storage_root)
          File.rm_rf!(target)
          File.mkdir_p!(Path.dirname(target))
          File.cp_r!(Path.join(storage_tmp, entry), target)

        :error ->
          Logger.warning(
            "snapshot contains storage for #{entry}, which is not an enabled " <>
              "storage module — skipped"
          )
      end
    end

    :ok
  end

  # Honors :storage_dirs overrides only when restoring into the live root.
  defp storage_dir_for(module_id, storage_root) do
    if storage_root == Application.get_env(:sapo_core, :storage_root) do
      Storage.dir(module_id)
    else
      Path.join(storage_root, to_string(module_id))
    end
  end

  defp ls_or_empty(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, _} -> []
    end
  end

  defp read_manifest(tmp) do
    path = Path.join(tmp, "manifest.json")

    with {:ok, raw} <- File.read(path),
         {:ok, %{"manifest_version" => _} = manifest} <- Jason.decode(raw) do
      {:ok, manifest}
    else
      {:error, :enoent} -> {:error, :manifest_missing}
      {:error, %Jason.DecodeError{}} -> {:error, :manifest_invalid}
      {:ok, _} -> {:error, :manifest_invalid}
      other -> other
    end
  end

  defp manifest do
    %{
      manifest_version: @manifest_version,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      modules:
        for mod <- Registry.modules() do
          %{id: mod.id(), title: mod.title(), version: mod.version()}
        end,
      migration_versions: migration_versions()
    }
  end

  defp migration_versions do
    Repo.query!("SELECT version FROM schema_migrations ORDER BY version")
    |> Map.get(:rows)
    |> List.flatten()
  rescue
    _ -> []
  end

  defp snapshots_dir, do: Application.fetch_env!(:sapo_core, :snapshots_dir)
end
