defmodule SapoCore.PrefsTest do
  use ExUnit.Case, async: false

  alias SapoCore.Prefs

  setup do
    on_exit(fn -> File.rm(Application.fetch_env!(:sapo_core, :prefs_overlay)) end)
    :ok
  end

  test "get falls back to default, put overrides, broadcast fires" do
    SapoKit.PubSub.subscribe("prefs")

    assert Prefs.get("statusline.core.snapshot", true) == true

    :ok = Prefs.put("statusline.core.snapshot", false)
    assert Prefs.get("statusline.core.snapshot", true) == false
    assert_receive {:pref_changed, "statusline.core.snapshot", false}

    assert Prefs.all()["statusline.core.snapshot"] == false
  end

  test "overlay wins over base" do
    base = Path.join(System.tmp_dir!(), "prefs_base_#{System.unique_integer([:positive])}.json")
    File.write!(base, Jason.encode!(%{"dashboard_button.my_plate" => "status"}))
    previous = Application.get_env(:sapo_core, :prefs_base)
    Application.put_env(:sapo_core, :prefs_base, base)

    on_exit(fn ->
      File.rm(base)

      case previous do
        nil -> Application.delete_env(:sapo_core, :prefs_base)
        val -> Application.put_env(:sapo_core, :prefs_base, val)
      end
    end)

    assert Prefs.get("dashboard_button.my_plate", "default") == "status"

    :ok = Prefs.put("dashboard_button.my_plate", "default")
    assert Prefs.get("dashboard_button.my_plate") == "default"
  end
end
