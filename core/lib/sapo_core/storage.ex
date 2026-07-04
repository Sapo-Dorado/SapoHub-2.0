defmodule SapoCore.Storage do
  @moduledoc """
  Module file storage under one root (`config :sapo_core, :storage_root`).

  Each module declares the directories it owns via `storage_paths/0`
  (relative to the root). They are created at boot and included in
  snapshots (M5).
  """

  alias SapoCore.Generated.Registry

  @doc "The storage root directory."
  @spec root() :: String.t()
  def root do
    Application.fetch_env!(:sapo_core, :storage_root)
  end

  @doc "Absolute path inside a module's storage area."
  @spec path(module_id :: atom(), relative :: String.t()) :: String.t()
  def path(module_id, relative \\ "") when is_atom(module_id) do
    Path.join([root(), to_string(module_id), relative])
  end

  @doc "Create the root and every enabled module's declared directories."
  @spec ensure_dirs!([module()]) :: :ok
  def ensure_dirs!(modules \\ Registry.modules()) do
    File.mkdir_p!(root())

    for mod <- modules, rel <- mod.storage_paths() do
      File.mkdir_p!(Path.join(root(), rel))
    end

    :ok
  end
end
