defmodule Mix.Tasks.Sapo.Gen.Migration do
  @shortdoc "Generates a migration file whose version can't collide with another module's"
  @moduledoc """
  Generates a new migration file in `priv/migrations`, the same way
  `mix ecto.gen.migration` does, except the version is
  `<14-digit-UTC-timestamp><3-digit-module-tag>` instead of just the
  timestamp.

  The module tag is `rem(:erlang.crc32(Atom.to_string(app)), 900) + 100`,
  where `app` is this project's `Mix.Project.config()[:app]` (which every
  SapoHub util module already sets to its `SapoKit.Module.id()`, so the
  tag is stable for a given module and effectively unique across the
  small set of modules any one deployment enables).

  This is why `mix ecto.gen.migration`'s plain timestamp-collision problem
  (two modules picking the same second, or copy-pasting a template
  without changing it — exactly what happened to
  `magic_proxies`/`youtube_download`'s `20260713120000`) can't happen here
  even by accident: the version is namespaced by module identity, not
  just wall-clock time. `SapoCore.Release.assert_unique_versions!/1` still
  runs at boot as a safety net (it'll still catch a hand-edited version
  that removes the tag), but this task is the first line of defense.

  Deliberately NOT a runtime rewrite of migration versions — an already
  *applied* migration's version is permanent (it's the primary key in
  `schema_migrations`); changing how versions are computed for existing
  files would make Ecto think they're new pending migrations and try to
  re-run them. This task only affects the filename chosen at the moment
  a NEW migration is generated, so it's fully backward compatible with
  core/my_plate/storage's already-applied migrations.

  ## Usage

      mix sapo.gen.migration create_magic_proxies

  Run from the module's own project root (same as `mix ecto.gen.migration`).
  """

  use Mix.Task

  @impl true
  def run([name | _] = _args) when is_binary(name) do
    app = Mix.Project.config()[:app]

    unless app do
      Mix.raise("no :app found in Mix.Project.config/0 — run this from a module's project root")
    end

    tag = rem(:erlang.crc32(Atom.to_string(app)), 900) + 100
    timestamp = utc_timestamp()
    version = "#{timestamp}#{tag}"

    underscored = Macro.underscore(name)
    dir = Path.join("priv", "migrations")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{version}_#{underscored}.exs")

    module_name =
      "#{Macro.camelize(Atom.to_string(app))}.Migrations.#{Macro.camelize(name)}"

    File.write!(path, """
    defmodule #{module_name} do
      use Ecto.Migration

      def change do
      end
    end
    """)

    Mix.shell().info("* creating #{path}")
    Mix.shell().info("  module tag #{tag} (from app #{inspect(app)}), version #{version}")
  end

  def run(_args) do
    Mix.raise("expected a migration name, e.g. mix sapo.gen.migration create_things")
  end

  defp utc_timestamp do
    {{y, mo, d}, {h, mi, s}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [y, mo, d, h, mi, s])
    |> List.to_string()
  end
end
