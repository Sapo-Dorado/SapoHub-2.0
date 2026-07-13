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

  @doc "Delete the file or folder at an API path (`<module_id>/<relative>`), across any opted-in module."
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(api_path), do: impl().delete_file(api_path)

  @doc """
  List the immediate contents (subfolders + files) at an API path.
  `""` or `nil` lists the top level — one entry per opted-in module.
  Uniform across modules: every opted-in module's storage is just a plain
  folder tree, browsable and manageable the same way.
  """
  @spec list_dir(String.t() | nil) ::
          {:ok, %{dirs: [map()], files: [map()]}} | {:error, :invalid_path}
  def list_dir(api_path), do: impl().list_dir(api_path)

  @doc "Create a folder at an API path (`<module_id>/<relative>`), across any opted-in module."
  @spec mkdir(String.t()) :: :ok | {:error, term()}
  def mkdir(api_path), do: impl().mkdir(api_path)

  @doc """
  Resolve an API path to an absolute *directory* path — unlike `resolve/1`,
  this also accepts a bare module id (its storage root), not just a nested
  file/folder path.
  """
  @spec resolve_dir(String.t()) :: {:ok, String.t()} | {:error, :invalid_path}
  def resolve_dir(api_path), do: impl().resolve_dir(api_path)

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :storage)
end
