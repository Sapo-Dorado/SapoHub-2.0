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

  @doc "Delete the file at an API path."
  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(api_path) do
    with {:ok, abs} <- resolve(api_path),
         true <- File.regular?(abs) || {:error, :not_found} do
      File.rm(abs)
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
