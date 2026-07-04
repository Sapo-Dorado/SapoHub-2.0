defmodule SapoCore.SecretsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SapoCore.Secrets

  defmodule NeedyModule do
    use SapoKit.Module
    def id, do: :needy
    def title, do: "Needy"
    def required_secrets, do: ["NEEDY_TOKEN"]
  end

  test "evaluate/3 reports set and missing secrets per owner" do
    status = Secrets.evaluate([NeedyModule], ["CORE_KEY"], %{"CORE_KEY" => "x"})

    assert %{var: "CORE_KEY", required_by: :core, set?: true} in status
    assert %{var: "NEEDY_TOKEN", required_by: :needy, set?: false} in status
  end

  test "empty string counts as missing" do
    assert [%{set?: false}] = Secrets.evaluate([], ["CORE_KEY"], %{"CORE_KEY" => ""})
  end

  test "validate! raises when a core secret is missing" do
    assert_raise RuntimeError, ~r/missing required core secrets: CORE_KEY/, fn ->
      Secrets.validate!([], ["CORE_KEY"], %{})
    end
  end

  test "validate! warns (but passes) on missing module secrets and stores status" do
    log =
      capture_log(fn ->
        status = Secrets.validate!([NeedyModule], [], %{})
        assert [%{var: "NEEDY_TOKEN", required_by: :needy, set?: false}] = status
      end)

    assert log =~ "NEEDY_TOKEN"
    assert log =~ "needy"
    assert [%{var: "NEEDY_TOKEN", set?: false}] = Secrets.status()
  end

  test "validate! is silent when everything is set" do
    log =
      capture_log(fn ->
        Secrets.validate!([NeedyModule], ["CORE_KEY"], %{
          "CORE_KEY" => "a",
          "NEEDY_TOKEN" => "b"
        })
      end)

    refute log =~ "NEEDY_TOKEN"
    assert Enum.all?(Secrets.status(), & &1.set?)
  end
end
