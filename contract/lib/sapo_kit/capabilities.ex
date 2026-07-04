defmodule SapoKit.Capabilities do
  @moduledoc """
  Cross-module integration point.

  Modules declare what they PROVIDE via `c:SapoKit.Module.capabilities/0`
  (e.g. `[reminders: MyReminders.CapabilityImpl]`). At boot, core collects
  these into a capability map. Consumers look implementations up here and
  degrade gracefully when a capability has no provider:

      case SapoKit.Capabilities.get(:reminders) do
        {:ok, reminders} -> reminders.schedule(%{...})
        :error -> :ok
      end

  Capability behaviours (the contracts both sides agree on) also live in
  this package — see `SapoKit.Capability.Reminders`.
  """

  @doc "Look up the provider for `capability`. Returns `:error` when absent."
  @spec get(atom()) :: {:ok, module()} | :error
  def get(capability) when is_atom(capability) do
    Map.fetch(all(), capability)
  end

  @doc "Like `get/1` but raises when the capability has no provider."
  @spec fetch!(atom()) :: module()
  def fetch!(capability) when is_atom(capability) do
    case get(capability) do
      {:ok, impl} ->
        impl

      :error ->
        raise KeyError,
              "no enabled module provides the #{inspect(capability)} capability " <>
                "(available: #{inspect(Map.keys(all()))})"
    end
  end

  @doc "The full capability map, keyed by capability name."
  @spec all() :: %{atom() => module()}
  def all do
    Application.get_env(:sapo_module_kit, :capabilities, %{})
  end
end
