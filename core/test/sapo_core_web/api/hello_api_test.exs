defmodule SapoCoreWeb.Api.HelloApiTest do
  @moduledoc """
  Exercises a module-contributed API end-to-end through core's router.
  """
  use SapoCoreWeb.ConnCase, async: true

  test "module API routes are mounted under /api", %{conn: conn} do
    conn = post(conn, "/api/hello", %{name: "world"})
    assert %{"id" => id, "name" => "world"} = json_response(conn, 201)

    conn = get(build_conn(), "/api/hello")
    assert [%{"id" => ^id}] = json_response(conn, 200)

    conn = delete(build_conn(), "/api/hello/#{id}")
    assert response(conn, 204)

    conn = get(build_conn(), "/api/hello")
    assert [] = json_response(conn, 200)
  end

  test "validation errors return 422 with formatted errors", %{conn: conn} do
    conn = post(conn, "/api/hello", %{})
    assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
  end
end
