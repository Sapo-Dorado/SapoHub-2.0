defmodule SapoKit.Storage do
  @moduledoc """
  Core file storage facade.

  Each module owns one directory (default `<storage root>/<module id>`,
  overridable in the hub config). The filesystem is the source of truth:
  write ordinary files, and they show up in the storage API/CLI and in
  snapshots automatically.

      dir = SapoKit.Storage.dir(:my_plate)
      File.write!(Path.join(dir, "export.csv"), csv)

  Subdirectories a module wants pre-created are declared via
  `c:SapoKit.Module.storage_paths/0` (relative to the module's dir).
  """

  @doc "The module's storage directory (created at boot)."
  @spec dir(atom()) :: String.t()
  def dir(module_id) when is_atom(module_id), do: impl().dir(module_id)

  @doc "Absolute path inside the module's storage directory."
  @spec path(atom(), String.t()) :: String.t()
  def path(module_id, relative) when is_atom(module_id), do: impl().path(module_id, relative)

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :storage)
end
