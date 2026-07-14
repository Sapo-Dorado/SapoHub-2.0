defmodule SapoCoreWeb.Api.RemindersApiTest do
  use SapoCoreWeb.ConnCase, async: false

  test "reminders CRUD + cancel round trip", %{conn: conn} do
    conn1 =
      post(conn, ~p"/api/reminders", %{
        "message" => "water plants",
        "remind_at" => "2026-08-01T09:00:00Z",
        "time_specific" => true
      })

    assert %{"id" => id, "status" => "pending", "message" => "water plants"} =
             json_response(conn1, 201)

    assert [%{"id" => ^id}] = json_response(get(conn, ~p"/api/reminders?status=pending"), 200)
    assert %{"id" => ^id} = json_response(get(conn, ~p"/api/reminders/#{id}"), 200)

    conn2 = patch(conn, ~p"/api/reminders/#{id}", %{"message" => "water plants!"})
    assert json_response(conn2, 200)["message"] == "water plants!"

    conn3 = delete(conn, ~p"/api/reminders/#{id}")
    assert json_response(conn3, 200)["status"] == "cancelled"

    assert json_response(get(conn, ~p"/api/reminders?status=pending"), 200) == []
  end

  test "validation errors are 422" do
    conn = build_conn()
    conn = post(conn, ~p"/api/reminders", %{"message" => ""})
    assert %{"errors" => %{"message" => _}} = json_response(conn, 422)
  end

  test "show/update/cancel on unknown id is 404" do
    conn = build_conn()
    id = Ecto.UUID.generate()

    assert json_response(get(conn, ~p"/api/reminders/#{id}"), 404)
    assert json_response(patch(build_conn(), ~p"/api/reminders/#{id}", %{"message" => "x"}), 404)
    assert json_response(delete(build_conn(), ~p"/api/reminders/#{id}"), 404)
  end
end
