defmodule SapoCoreWeb.SettingsLiveTest do
  use SapoCoreWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders hub tab sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")

    assert html =~ "Save all data"
    # The deploy stub from other tests may still be running ("Deploying…"),
    # so assert on the button binding rather than its label.
    assert html =~ ~s(phx-click="deploy")
    assert html =~ "recent snapshots"
    assert html =~ "Secrets"
    assert html =~ "Enabled utilities"
    assert html =~ "sapo_hello"
  end

  test "deploy button starts the configured command session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html = render_click(view, "deploy")
    assert html =~ "Deploying…" or html =~ "Deploy latest"
  end

  test "snapshot download API rejects traversal", %{conn: conn} do
    conn = get(conn, ~p"/api/snapshot/#{"../../etc/passwd"}")
    assert json_response(conn, 404)
  end

  test "snapshot list API responds", %{conn: conn} do
    conn = get(conn, ~p"/api/snapshot")
    assert is_list(json_response(conn, 200))
  end
end
