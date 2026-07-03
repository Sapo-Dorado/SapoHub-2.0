defmodule SapoCoreWeb.DashboardLiveTest do
  use SapoCoreWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a tile for each enabled module with a dashboard tile", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "SapoHub"
    assert html =~ "tile-sapo_hello"
    assert html =~ "Hello"
  end

  test "tile navigates to the module page within the shared live_session", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # live_redirect (not a full page load) proves both routes share :default
    {:ok, _hello_view, html} =
      view
      |> element("#tile-sapo_hello")
      |> render_click()
      |> follow_redirect(conn, "/hello")

    assert html =~ "Hello Module"
  end

  test "badges are loaded after mount", %{conn: conn} do
    {:ok, _} = SapoHello.create_greeting(%{name: "badge-test"})

    {:ok, view, _html} = live(conn, "/")

    # the badge is computed in handle_info(:load_badges, ...) after mount
    assert render(view) =~ "badge"
  end
end
