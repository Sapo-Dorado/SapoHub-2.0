defmodule Mix.Tasks.Sapo.Gen.ModuleTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Sapo.Gen.Module, as: Gen

  test "generates the full module skeleton" do
    files = Gen.files("my_thing")

    assert Map.has_key?(files, "mix.exs")
    assert Map.has_key?(files, "lib/my_thing/module.ex")
    assert Map.has_key?(files, "lib/my_thing_web/live/index.ex")
    assert Map.has_key?(files, "priv/cli/fragment.sh")
    assert Map.has_key?(files, "assets/hooks.js")

    assert files["mix.exs"] =~ "app: :my_thing"
    assert files["mix.exs"] =~ ~s({:sapo_module_kit, path: "../../contract"})

    module_ex = files["lib/my_thing/module.ex"]
    assert module_ex =~ "defmodule MyThing.Module"
    assert module_ex =~ "use SapoKit.Module"
    assert module_ex =~ "def id, do: :my_thing"
    assert module_ex =~ ~s(path: "/my-thing")
    assert module_ex =~ "MyThingWeb.Live.Index"
  end

  test "respects title and kit_path options" do
    files = Gen.files("my_thing", title: "My Fancy Thing", kit_path: "../deps/contract")

    assert files["lib/my_thing/module.ex"] =~ ~s(def title, do: "My Fancy Thing")
    assert files["mix.exs"] =~ ~s(path: "../deps/contract")
  end

  test "generated live view uses the shared statusline navbar" do
    files = Gen.files("my_thing")

    live = files["lib/my_thing_web/live/index.ex"]
    assert live =~ "use SapoKit.Web, :live_view"
    assert live =~ "SapoCoreWeb.Statusline.statusline"
    assert live =~ ~s(crumb="mything")
    refute live =~ "<Layouts.app"
  end
end
