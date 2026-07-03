defmodule SapoCoreWeb.ModuleRouterTest do
  use ExUnit.Case, async: true

  alias SapoCoreWeb.ModuleRouter

  defmodule FakeModA, do: def(id, do: :fake_a)
  defmodule FakeModB, do: def(id, do: :fake_b)

  defp ui_route(path), do: %{path: path, live_view: SomeLive, action: :index}

  defp api_route(verb, path),
    do: %{verb: verb, path: path, controller: SomeController, action: :index}

  describe "check_ui_routes!/1" do
    test "accepts distinct paths" do
      assert :ok ==
               ModuleRouter.check_ui_routes!([
                 {FakeModA, ui_route("/a")},
                 {FakeModB, ui_route("/b")}
               ])
    end

    test "raises when two modules claim the same path, naming both" do
      err =
        assert_raise CompileError, fn ->
          ModuleRouter.check_ui_routes!([
            {FakeModA, ui_route("/dup")},
            {FakeModB, ui_route("/dup")}
          ])
        end

      assert err.description =~ "FakeModA"
      assert err.description =~ "FakeModB"
      assert err.description =~ "/dup"
    end

    test "raises when a module claims a reserved core path" do
      assert_raise CompileError, ~r/reserved by SapoHub core/, fn ->
        ModuleRouter.check_ui_routes!([{FakeModA, ui_route("/settings")}])
      end
    end

    test "allows the same module to declare multiple actions on one path" do
      assert :ok ==
               ModuleRouter.check_ui_routes!([
                 {FakeModA, ui_route("/a")},
                 {FakeModA, ui_route("/a")}
               ])
    end
  end

  describe "check_api_routes!/1" do
    test "same path with different verbs is fine" do
      assert :ok ==
               ModuleRouter.check_api_routes!([
                 {FakeModA, api_route(:get, "/things")},
                 {FakeModA, api_route(:post, "/things")}
               ])
    end

    test "raises on cross-module verb+path duplicate" do
      assert_raise CompileError, ~r/declared by multiple modules/, fn ->
        ModuleRouter.check_api_routes!([
          {FakeModA, api_route(:get, "/things")},
          {FakeModB, api_route(:get, "/things")}
        ])
      end
    end

    test "raises on reserved API path" do
      assert_raise CompileError, ~r/reserved by SapoHub core/, fn ->
        ModuleRouter.check_api_routes!([{FakeModA, api_route(:post, "/notify")}])
      end
    end
  end
end
