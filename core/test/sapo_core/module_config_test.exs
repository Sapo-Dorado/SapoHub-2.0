defmodule SapoCore.ModuleConfigTest do
  use ExUnit.Case, async: true

  defmodule StrictModule do
    use SapoKit.Module
    def id, do: :strict
    def title, do: "Strict"

    def config_schema do
      [
        tile_style: [type: {:in, [:standard, :wide]}, default: :standard],
        limit: [type: :pos_integer, default: 10]
      ]
    end
  end

  defmodule LaxModule do
    use SapoKit.Module
    def id, do: :lax
    def title, do: "Lax"
  end

  test "valid config passes" do
    assert :ok =
             SapoCore.ModuleConfig.validate!([StrictModule], %{
               strict: %{tile_style: :wide, limit: 5}
             })
  end

  test "missing optional keys pass (schema defaults)" do
    assert :ok = SapoCore.ModuleConfig.validate!([StrictModule], %{})
  end

  test "string keys (nix-serialized) are accepted" do
    assert :ok = SapoCore.ModuleConfig.validate!([StrictModule], %{strict: %{"limit" => 3}})
  end

  test "invalid config fails fast naming the module" do
    assert_raise ArgumentError, ~r/invalid config for module :strict/, fn ->
      SapoCore.ModuleConfig.validate!([StrictModule], %{strict: %{tile_style: :bogus}})
    end

    assert_raise ArgumentError, ~r/unknown options/, fn ->
      SapoCore.ModuleConfig.validate!([StrictModule], %{strict: %{nope: 1}})
    end
  end

  test "empty schema accepts anything" do
    assert :ok = SapoCore.ModuleConfig.validate!([LaxModule], %{lax: %{whatever: true}})
  end
end
