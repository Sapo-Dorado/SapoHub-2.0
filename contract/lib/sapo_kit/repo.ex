defmodule SapoKit.Repo do
  @moduledoc """
  Facade over the host application's Ecto repo.

  Util modules cannot depend on `:sapo_core` (core depends on them), so they
  talk to the database through this facade. Core points it at the real repo:

      config :sapo_module_kit, repo: SapoCore.Repo
  """

  defp repo, do: Application.fetch_env!(:sapo_module_kit, :repo)

  def aggregate(queryable, aggregate, opts \\ []), do: repo().aggregate(queryable, aggregate, opts)
  def all(queryable, opts \\ []), do: repo().all(queryable, opts)
  def delete(struct, opts \\ []), do: repo().delete(struct, opts)
  def delete!(struct, opts \\ []), do: repo().delete!(struct, opts)
  def delete_all(queryable, opts \\ []), do: repo().delete_all(queryable, opts)
  def exists?(queryable, opts \\ []), do: repo().exists?(queryable, opts)
  def get(queryable, id, opts \\ []), do: repo().get(queryable, id, opts)
  def get!(queryable, id, opts \\ []), do: repo().get!(queryable, id, opts)
  def get_by(queryable, clauses, opts \\ []), do: repo().get_by(queryable, clauses, opts)
  def get_by!(queryable, clauses, opts \\ []), do: repo().get_by!(queryable, clauses, opts)
  def insert(struct, opts \\ []), do: repo().insert(struct, opts)
  def insert!(struct, opts \\ []), do: repo().insert!(struct, opts)
  def insert_all(schema, entries, opts \\ []), do: repo().insert_all(schema, entries, opts)
  def one(queryable, opts \\ []), do: repo().one(queryable, opts)
  def one!(queryable, opts \\ []), do: repo().one!(queryable, opts)
  def preload(struct_or_structs, preloads, opts \\ []), do: repo().preload(struct_or_structs, preloads, opts)
  def query(sql, params \\ [], opts \\ []), do: repo().query(sql, params, opts)
  def query!(sql, params \\ [], opts \\ []), do: repo().query!(sql, params, opts)
  def reload(struct, opts \\ []), do: repo().reload(struct, opts)
  def rollback(value), do: repo().rollback(value)
  def stream(queryable, opts \\ []), do: repo().stream(queryable, opts)
  def transaction(fun_or_multi, opts \\ []), do: repo().transaction(fun_or_multi, opts)
  def update(changeset, opts \\ []), do: repo().update(changeset, opts)
  def update!(changeset, opts \\ []), do: repo().update!(changeset, opts)
  def update_all(queryable, updates, opts \\ []), do: repo().update_all(queryable, updates, opts)
end
