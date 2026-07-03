defmodule SapoCore.Release do
  @moduledoc """
  Tasks that run in a release context (no Mix available): migrations across
  core + all enabled modules' migration paths, and (from M5) snapshot
  restore staging.
  """

  @app :sapo_core

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
  filtered to those that exist. Raises if two migration files share a
  version number (modules must use full-timestamp versions).
  """
  def migration_paths do
    core = Application.app_dir(@app, "priv/repo/migrations")

    module_paths =
      for mod <- SapoCore.Generated.Registry.modules(),
          path = mod.migrations_path(),
          File.dir?(path) do
        path
      end

    paths = Enum.filter([core | module_paths], &File.dir?/1)
    assert_unique_versions!(paths)
    paths
  end

  defp assert_unique_versions!(paths) do
    paths
    |> Enum.flat_map(fn path ->
      path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".exs"))
      |> Enum.map(fn file ->
        [version | _] = String.split(file, "_", parts: 2)
        {version, Path.join(path, file)}
      end)
    end)
    |> Enum.group_by(fn {version, _file} -> version end)
    |> Enum.each(fn {version, entries} ->
      unless match?([_], entries) do
        files = Enum.map(entries, fn {_v, f} -> f end) |> Enum.join(", ")

        raise "duplicate migration version #{version} across modules: #{files}. " <>
                "Modules must use unique full-timestamp migration versions."
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
