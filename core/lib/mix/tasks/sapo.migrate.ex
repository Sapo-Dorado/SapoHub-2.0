defmodule Mix.Tasks.Sapo.Migrate do
  @shortdoc "Runs migrations for core and all enabled util modules"

  @moduledoc """
  Like `mix ecto.migrate`, but includes every enabled module's migrations
  path (see `SapoCore.Release.migration_paths/0`).
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    for repo <- Application.fetch_env!(:sapo_core, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, SapoCore.Release.migration_paths(), :up, all: true)
        )
    end

    :ok
  end
end
