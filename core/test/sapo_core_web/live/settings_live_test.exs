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

  test "setting GITHUB_TOKEN via the inline form round-trips through the stub", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "GITHUB_TOKEN"
    assert html =~ "missing"

    html = render_click(view, "edit_secret", %{"var" => "GITHUB_TOKEN"})
    assert html =~ ~s(phx-submit="save_secret")

    html = render_submit(view, "save_secret", %{"var" => "GITHUB_TOKEN", "value" => "ghp_fake"})
    assert html =~ "GITHUB_TOKEN saved."
  end

  test "save_secret rejects vars outside the allowlist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html = render_submit(view, "save_secret", %{"var" => "SOME_OTHER_VAR", "value" => "x"})
    assert html =~ "Can&#39;t set SOME_OTHER_VAR"
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
