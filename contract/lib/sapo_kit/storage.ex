defmodule SapoKit.Storage do
  @moduledoc """
  Core file storage facade.

  Storage is OPT-IN: declare a non-empty `c:SapoKit.Module.storage_paths/0`
  (`["."]` for just a directory) and your module gets a dedicated directory
  (default `<storage root>/<module id>`, overridable in the hub config).
  The filesystem is the source of truth: write ordinary files, and they
  show up in the storage API/CLI and in snapshots automatically.

      dir = SapoKit.Storage.dir(:my_plate)
      File.write!(Path.join(dir, "export.csv"), csv)

  Modules that have not opted in have no storage directory.
  """

  @doc "The module's storage directory (created at boot)."
  @spec dir(atom()) :: String.t()
  def dir(module_id) when is_atom(module_id), do: impl().dir(module_id)

  @doc "Absolute path inside the module's storage directory."
  @spec path(atom(), String.t()) :: String.t()
  def path(module_id, relative) when is_atom(module_id), do: impl().path(module_id, relative)

  @doc """
  All files across every module that has opted into storage.

  Cross-module visibility, unlike `dir/1`/`path/2`. Deliberately exposed
  for building visibility/admin tooling (e.g. the `storage` module's file
  browser) — most modules should never need this; reach for `dir/1` first.
  """
  @spec list_all() :: [%{path: String.t(), size: non_neg_integer(), mtime: DateTime.t()}]
  def list_all, do: impl().list_files()

  @doc """
  Resolve an API path (`<module_id>/<relative>`) to an absolute file path.
  Rejects traversal outside the owning module's dir and unknown modules.
  """
  @spec resolve(String.t()) :: {:ok, String.t()} | {:error, :invalid_path}
  def resolve(api_path), do: impl().resolve(api_path)

  @doc "Delete the file at an API path (`<module_id>/<relative>`), across any opted-in module."
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(api_path), do: impl().delete_file(api_path)

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :storage)
end
