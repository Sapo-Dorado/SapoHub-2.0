defmodule SapoCore.Capabilities do
  @moduledoc """
  Builds the capability map at boot from each enabled module's
  `capabilities/0` and publishes it where `SapoKit.Capabilities` reads it.

  Two modules providing the same capability is a configuration error and
  fails the boot with both module names.
  """

  alias SapoCore.Generated.Registry

  @doc "Collect, verify and publish the capability map. Returns it."
  @spec build!([module()]) :: %{atom() => module()}
  def build!(modules \\ Registry.modules()) do
    {caps, _providers} =
      Enum.reduce(modules, {%{}, %{}}, fn mod, acc ->
        Enum.reduce(mod.capabilities(), acc, fn {cap, impl}, {caps, providers} ->
          case providers do
            %{^cap => other} ->
              raise ArgumentError,
                    "capability #{inspect(cap)} is provided by both " <>
                      "#{inspect(other)} and #{inspect(mod)}; enable only one provider"

            _ ->
              {Map.put(caps, cap, impl), Map.put(providers, cap, mod)}
          end
        end)
      end)

    Application.put_env(:sapo_module_kit, :capabilities, caps)
    caps
  end
end
