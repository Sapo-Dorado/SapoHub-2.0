defmodule SapoCore.Generated.Registry do
  @moduledoc """
  The enabled-module registry.

  This checked-in version is the DEV default. In a Nix-composed release
  build, Nix generates this file from the user's config — module list in
  dependency order plus each module's serialized options. It must stay in
  sync with `config/modules.lock.exs`.
  """

  @doc "Enabled `SapoKit.Module` implementations, in dependency order."
  def modules do
    [SapoHello.Module, MyPlate.Module, Storage.Module, Reminders.Module]
  end

  @doc "Per-module config maps, keyed by module id."
  def module_config do
    %{sapo_hello: %{}, my_plate: %{}, storage: %{}, reminders: %{}}
  end

  @doc "Config map for one module (empty map when unset)."
  def config_for(mod) when is_atom(mod) do
    Map.get(module_config(), mod.id(), %{})
  end
end
