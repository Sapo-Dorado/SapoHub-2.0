defmodule SapoCore.Storage do
  @moduledoc """
  Core file storage (backs `SapoKit.Storage`). v1-shaped: the filesystem is
  the source of truth.

  Storage is OPT-IN: only modules with a non-empty `storage_paths/0` get a
  directory — `<storage root>/<module id>` by default, overridable per
  utility via `config :sapo_core, :storage_dirs, %{...}` (fed from the nix
  config / prefs). `storage_paths/0` entries are subdirs to pre-create
  (`["."]` = just the dir). Everything under opted-in dirs is listed by the
  file API and included in snapshots (M5).
  """

  alias SapoCore.Generated.Registry

  @doc "The storage root directory."
  @spec root() :: String.t()
  def root, do: Application.fetch_env!(:sapo_core, :storage_root)

  @doc "A module's storage directory (config override or `<root>/<id>`)."
  @spec dir(atom()) :: String.t()
  def dir(module_id) when is_atom(module_id) do
    overrides = Application.get_env(:sapo_core, :storage_dirs, %{})

    Map.get(overrides, module_id) ||
      Map.get(overrides, to_string(module_id)) ||
      Path.join(root(), to_string(module_id))
  end

  @doc "Absolute path inside a module's storage directory."
  @spec path(atom(), String.t()) :: String.t()
  def path(module_id, relative \\ "") when is_atom(module_id) do
    Path.join(dir(module_id), relative)
  end

  @doc "Create the root plus dir + declared subdirs for opted-in modules."
  @spec ensure_dirs!([module()]) :: :ok
  def ensure_dirs!(modules \\ Registry.modules()) do
    File.mkdir_p!(root())

    for mod <- storage_modules(modules) do
      base = dir(mod.id())
      File.mkdir_p!(base)
      for rel <- mod.storage_paths(), do: File.mkdir_p!(Path.join(base, rel))
    end

    :ok
  end

  @doc "Modules that opted into storage (non-empty `storage_paths/0`)."
  @spec storage_modules([module()]) :: [module()]
  def storage_modules(modules \\ Registry.modules()) do
    Enum.filter(modules, &(&1.storage_paths() != []))
  end

  # ── File API (used by /api/storage and the sapo CLI) ───────────────────────

  @typedoc "API paths are `<module_id>/<relative path>`."
  @type entry :: %{path: String.t(), size: non_neg_integer(), mtime: DateTime.t()}

  @doc "All files across opted-in modules' storage dirs."
  @spec list_files([module()]) :: [entry()]
  def list_files(modules \\ Registry.modules()) do
    modules
    |> storage_modules()
    |> Enum.flat_map(fn mod ->
      base = dir(mod.id())

      base
      |> walk()
      |> Enum.map(fn abs ->
        stat = File.stat!(abs, time: :posix)

        %{
          path: Path.join(to_string(mod.id()), Path.relative_to(abs, base)),
          size: stat.size,
          mtime: DateTime.from_unix!(stat.mtime)
        }
      end)
    end)
    |> Enum.sort_by(& &1.path)
  end

  @doc """
  Resolve an API path (`<module_id>/<relative>`) to an absolute file path.
  Rejects traversal outside the module's dir, unknown modules, and modules
  that have not opted into storage.
  """
  @spec resolve(String.t(), [module()]) :: {:ok, String.t()} | {:error, :invalid_path}
  def resolve(api_path, modules \\ Registry.modules()) do
    with [module_part | rest] when rest != [] <- Path.split(api_path),
         %{} = mod <- find_module(storage_modules(modules), module_part) do
      base = Path.expand(dir(mod.id))
      abs = Path.expand(Path.join([base | rest]))

      if String.starts_with?(abs, base <> "/") do
        {:ok, abs}
      else
        {:error, :invalid_path}
      end
    else
      _ -> {:error, :invalid_path}
    end
  end

  @doc "Delete the file or folder at an API path."
  @spec delete_file(String.t(), [module()]) :: :ok | {:error, term()}
  def delete_file(api_path, modules \\ Registry.modules()) do
    with {:ok, abs} <- resolve(api_path, modules) do
      cond do
        File.regular?(abs) ->
          File.rm(abs)

        File.dir?(abs) ->
          case File.rm_rf(abs) do
            {:ok, _} -> :ok
            {:error, reason, _} -> {:error, reason}
          end

        true ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  List the immediate contents (subfolders + files) at an API path, relative
  to the storage root. `nil`/`""` lists the top level (one entry per
  opted-in module's storage dir — which lives directly under the storage
  root by default). Every level below is a plain, uniformly-browsable
  folder tree; there is no special handling per module.
  """
  @spec list_dir(String.t() | nil, [module()]) ::
          {:ok, %{dirs: [map()], files: [map()]}} | {:error, :invalid_path}
  def list_dir(api_path, modules \\ Registry.modules())

  def list_dir(empty, modules) when empty in [nil, ""] do
    dirs =
      modules
      |> storage_modules()
      |> Enum.map(fn mod ->
        name = to_string(mod.id())
        %{name: name, path: name, count: count_entries(dir(mod.id()))}
      end)
      |> Enum.sort_by(& &1.name)

    {:ok, %{dirs: dirs, files: []}}
  end

  def list_dir(api_path, modules) do
    with [module_part | rest] <- Path.split(api_path),
         %{} = mod <- find_module(storage_modules(modules), module_part) do
      base = Path.expand(dir(mod.id))
      abs = Path.expand(Path.join([base | rest]))

      if abs == base or String.starts_with?(abs, base <> "/") do
        list_dir_abs(abs, api_path)
      else
        {:error, :invalid_path}
      end
    else
      _ -> {:error, :invalid_path}
    end
  end

  defp list_dir_abs(abs, api_path) do
    case File.ls(abs) do
      {:ok, names} ->
        {dir_names, file_names} = Enum.split_with(names, &File.dir?(Path.join(abs, &1)))

        dirs =
          dir_names
          |> Enum.map(fn name ->
            %{name: name, path: Path.join(api_path, name), count: count_entries(Path.join(abs, name))}
          end)
          |> Enum.sort_by(& &1.name)

        files =
          file_names
          |> Enum.map(fn name ->
            full = Path.join(abs, name)
            stat = File.stat!(full, time: :posix)

            %{
              name: name,
              path: Path.join(api_path, name),
              size: stat.size,
              mtime: DateTime.from_unix!(stat.mtime)
            }
          end)
          |> Enum.sort_by(& &1.name)

        {:ok, %{dirs: dirs, files: files}}

      {:error, _} ->
        {:error, :invalid_path}
    end
  end

  defp count_entries(dir) do
    case File.ls(dir) do
      {:ok, entries} -> length(entries)
      _ -> 0
    end
  end

  @doc """
  Resolve an API path to an absolute *directory* path (unlike `resolve/2`,
  the path may point at a module's root, not just a nested file/folder).
  Rejects traversal outside the owning module's dir and unknown modules.
  """
  @spec resolve_dir(String.t(), [module()]) :: {:ok, String.t()} | {:error, :invalid_path}
  def resolve_dir(api_path, modules \\ Registry.modules()) do
    with [module_part | rest] <- Path.split(api_path),
         %{} = mod <- find_module(storage_modules(modules), module_part) do
      base = Path.expand(dir(mod.id))
      abs = Path.expand(Path.join([base | rest]))

      if abs == base or String.starts_with?(abs, base <> "/") do
        {:ok, abs}
      else
        {:error, :invalid_path}
      end
    else
      _ -> {:error, :invalid_path}
    end
  end

  @doc "Create a folder at an API path, relative to the storage root."
  @spec mkdir(String.t(), [module()]) :: :ok | {:error, term()}
  def mkdir(api_path, modules \\ Registry.modules()) do
    with [module_part | rest] when rest != [] <- Path.split(api_path),
         %{} = mod <- find_module(storage_modules(modules), module_part) do
      base = Path.expand(dir(mod.id))
      abs = Path.expand(Path.join([base | rest]))

      if String.starts_with?(abs, base <> "/") do
        File.mkdir_p(abs)
      else
        {:error, :invalid_path}
      end
    else
      _ -> {:error, :invalid_path}
    end
  end

  defp find_module(modules, id_string) do
    case Enum.find(modules, &(to_string(&1.id()) == id_string)) do
      nil -> nil
      mod -> %{id: mod.id()}
    end
  end

  defp walk(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        Enum.flat_map(names, fn name ->
          full = Path.join(dir, name)

          cond do
            File.dir?(full) -> walk(full)
            File.regular?(full) -> [full]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end
end
