defmodule SapoCore.CapabilitiesTest do
  use ExUnit.Case, async: false

  defmodule FakeReminders do
    @behaviour SapoKit.Capability.Reminders
    def schedule(_attrs), do: {:ok, :scheduled}
    def cancel_by_source(_source, _ref), do: :ok
    def update_by_source(_source, _ref, _changes), do: :ok
  end

  defmodule ProviderModule do
    use SapoKit.Module
    def id, do: :provider
    def title, do: "Provider"
    def capabilities, do: [reminders: SapoCore.CapabilitiesTest.FakeReminders]
  end

  defmodule RivalProvider do
    use SapoKit.Module
    def id, do: :rival
    def title, do: "Rival"
    def capabilities, do: [reminders: SomeOtherImpl]
  end

  setup do
    previous = Application.get_env(:sapo_module_kit, :capabilities)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:sapo_module_kit, :capabilities)
        map -> Application.put_env(:sapo_module_kit, :capabilities, map)
      end
    end)

    :ok
  end

  test "build! publishes provided capabilities for SapoKit.Capabilities" do
    SapoCore.Capabilities.build!([ProviderModule])

    assert {:ok, FakeReminders} = SapoKit.Capabilities.get(:reminders)
    assert SapoKit.Capabilities.fetch!(:reminders) == FakeReminders
    assert {:ok, :scheduled} = FakeReminders.schedule(%{})
  end

  test "consumers degrade gracefully when a capability is absent" do
    SapoCore.Capabilities.build!([])

    assert :error = SapoKit.Capabilities.get(:reminders)
    assert_raise KeyError, fn -> SapoKit.Capabilities.fetch!(:reminders) end
  end

  test "duplicate providers fail the boot with both module names" do
    assert_raise ArgumentError, ~r/ProviderModule.*RivalProvider/s, fn ->
      SapoCore.Capabilities.build!([ProviderModule, RivalProvider])
    end
  end
end
