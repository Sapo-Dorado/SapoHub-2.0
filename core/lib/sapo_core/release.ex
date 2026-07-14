defmodule SapoCore.Release do
  @moduledoc """
  Tasks that run in a release context (no Mix available): migrations across
  core + all enabled modules' migration paths, and (from M5) snapshot
  restore staging.
  """

  @app :sapo_core

  @doc """
  Boot-time snapshot restore (systemd ExecStartPre, BEFORE migrate/0).

  If a staged archive exists at `:restore_pending` (deploy `--snapshot`
  stages it there), restore it and remove the stage file. A failed restore
  leaves the stage file for inspection and raises so the boot aborts —
  `pre-restore-backup.sqlite3` sits next to the DB either way.
  """
  def maybe_restore do
    load_app()
    pending = Application.get_env(@app, :restore_pending)

    cond do
      is_nil(pending) or not File.exists?(pending) ->
        :ok

      true ->
        case SapoCore.Snapshot.restore_from(pending) do
          :ok ->
            File.rm!(pending)
            :ok

          {:error, reason} ->
            raise "snapshot restore from #{pending} failed: #{inspect(reason)}. " <>
                    "The previous DB is preserved as pre-restore-backup.sqlite3; " <>
                    "remove the staged file to boot without restoring."
        end
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, migration_paths(), :up, all: true)
        )
    end

    :ok
  end

  @doc """
  Core's migrations dir plus each enabled module's `migrations_path/0`,
  namespaced by module id so two modules can never collide on version,
  even by accident (e.g. a copy-pasted migration template that never got
  its timestamp edited -- what actually happened with magic_proxies and
  youtube_download both shipping `20260713120000`).

  Migration files live in the read-only Nix store, so they're copied into
  a scratch directory under `SapoCore.tmp_dir!/0` with the version
  rewritten to `<original-version><3-digit-module-tag>` (tag =
  `rem(crc32(id), 900) + 100`) before being handed to `Ecto.Migrator`.
  File CONTENT is untouched -- only the filename Ecto parses the version
  from changes.
  """
  def migration_paths do
    core = Application.app_dir(@app, "priv/repo/migrations")

    module_entries =
      for mod <- SapoCore.Generated.Registry.modules(),
          path = mod.migrations_path(),
          File.dir?(path) do
        {mod.id(), path}
      end

    entries =
      [{:core, core} | module_entries]
      |> Enum.filter(fn {_id, path} -> File.dir?(path) end)

    paths = namespace_migrations(entries)
    assert_unique_versions!(paths)
    paths
  end

  defp namespace_migrations(entries) do
    scratch_root = Path.join(SapoCore.tmp_dir!(), "sapohub-migrations")
    File.rm_rf!(scratch_root)

    Enum.map(entries, fn {id, path} ->
      tag = module_tag(id)
      dest = Path.join(scratch_root, Atom.to_string(id))
      File.mkdir_p!(dest)

      path
      |> File.ls!()
      |> Enum.filter(&migration_file?/1)
      |> Enum.each(fn file ->
        [version, rest] = String.split(file, "_", parts: 2)
        File.cp!(Path.join(path, file), Path.join(dest, "#{version}#{tag}_#{rest}"))
      end)

      dest
    end)
  end

  # A module's own id is already required to be globally unique (it's the
  # config key / table-name prefix, see SapoKit.Module.id/0), so hashing
  # it is enough to keep two modules from landing on the same tag without
  # needing any coordination between module authors.
  defp module_tag(id) do
    id
    |> Atom.to_string()
    |> :erlang.crc32()
    |> rem(900)
    |> Kernel.+(100)
  end

  # Migration files are named <digits>_<name>.exs -- excludes stray .exs
  # files that don't follow that shape (e.g. .formatter.exs).
  defp migration_file?(file), do: Regex.match?(~r/^\d+_.+\.exs$/, file)

  # Backstop, not the primary defense: namespacing by module id makes a
  # cross-module collision structurally near-impossible, but this still
  # catches a hash collision between two modules' tags, or two migrations
  # within the SAME module sharing a version (a real authoring mistake).
  defp assert_unique_versions!(paths) do
    paths
    |> Enum.flat_map(fn path ->
      path
      |> File.ls!()
      |> Enum.filter(&migration_file?/1)
      |> Enum.map(fn file ->
        [version | _] = String.split(file, "_", parts: 2)
        {version, Path.join(path, file)}
      end)
    end)
    |> Enum.group_by(fn {version, _file} -> version end)
    |> Enum.each(fn {version, entries} ->
      unless match?([_], entries) do
        files = Enum.map(entries, fn {_v, f} -> f end) |> Enum.join(", ")

        raise "duplicate migration version #{version}: #{files}. " <>
                "Either two migrations in the same module share a version, " <>
                "or two modules' tags collided (extremely unlikely) -- " <>
                "pick a different version for one of them."
      end
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_loaded(@app)
  end
end
