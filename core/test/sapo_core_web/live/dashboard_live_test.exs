defmodule SapoCoreWeb.DashboardLiveTest do
  use SapoCoreWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders a slot for each module with UI routes plus core slots", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(id="slot-sapo_hello")
    assert html =~ ~s(id="slot-my_plate")
    # Settings is NOT a tile — it's the statusline gear.
    refute html =~ ~s(id="slot-settings")
    assert html =~ ~s(href="/settings")
    # Assistant is NOT a tile either — it's the floating button in the
    # root layout, on every page.
    refute html =~ ~s(id="slot-assistant")
    assert html =~ ~s(id="floating-assistant")
  end

  test "statusline shows core and module items", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "scheduler ✓"
    assert html =~ "snapshot"
    assert html =~ "due"
  end

  test "slot navigates to the module page within the shared live_session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _module_view, module_html} =
      view
      |> element("#slot-sapo_hello")
      |> render_click()
      |> follow_redirect(conn, "/hello")

    assert module_html =~ "hello"
  end

  test "dashboard_button pref switches a slot to the module component", %{conn: conn} do
    :ok = SapoCore.Prefs.put("dashboard_button.my_plate", "preview")

    on_exit(fn ->
      File.rm(Application.fetch_env!(:sapo_core, :prefs_overlay))
    end)

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "no active tasks"

    :ok = SapoCore.Prefs.put("dashboard_button.my_plate", "default")
    {:ok, _view, html2} = live(conn, ~p"/")
    assert html2 =~ ~s(id="slot-my_plate")
  end
end
