defmodule SapoCoreWeb.Api.MyPlateApiTest do
  use SapoCoreWeb.ConnCase, async: false

  test "tasks CRUD + complete round trip", %{conn: conn} do
    conn1 =
      post(conn, ~p"/api/tasks", %{
        "title" => "api task",
        "priority" => "high",
        "due_date" => "2026-08-01"
      })

    assert %{"id" => id, "priority" => "high", "due_date" => "2026-08-01"} =
             json_response(conn1, 201)

    assert [%{"id" => ^id}] = json_response(get(conn, ~p"/api/tasks?priority=high"), 200)

    conn2 = patch(conn, ~p"/api/tasks/#{id}", %{"title" => "renamed"})
    assert json_response(conn2, 200)["title"] == "renamed"

    conn3 = post(conn, ~p"/api/tasks/#{id}/complete")
    assert json_response(conn3, 200)["completed"] == true
    assert json_response(get(conn, ~p"/api/tasks"), 200) == []

    conn4 = post(conn, ~p"/api/tasks/#{id}/uncomplete")
    assert json_response(conn4, 200)["completed"] == false

    conn5 = delete(conn, ~p"/api/tasks/#{id}")
    assert response(conn5, 204)
  end

  test "task validation errors are 422", %{conn: conn} do
    conn = post(conn, ~p"/api/tasks", %{"priority" => "high"})
    assert %{"errors" => %{"title" => _}} = json_response(conn, 422)

    conn2 = post(conn, ~p"/api/tasks", %{"title" => "x", "priority" => "urgent"})
    assert %{"errors" => %{"priority" => _}} = json_response(conn2, 422)
  end

  test "recurring tasks CRUD", %{conn: conn} do
    conn1 =
      post(conn, ~p"/api/recurring-tasks", %{
        "title" => "weekly review",
        "recurrence" => "weekly",
        "day_of_week" => 1,
        "active" => false
      })

    assert %{"id" => id, "recurrence" => "weekly"} = json_response(conn1, 201)

    conn2 = patch(conn, ~p"/api/recurring-tasks/#{id}", %{"title" => "weekly review!"})
    assert json_response(conn2, 200)["title"] == "weekly review!"

    assert Enum.any?(
             json_response(get(conn, ~p"/api/recurring-tasks"), 200),
             &(&1["id"] == id)
           )

    conn3 = delete(conn, ~p"/api/recurring-tasks/#{id}")
    assert response(conn3, 204)
  end

  test "weekly recurring without day_of_week is 422", %{conn: conn} do
    conn = post(conn, ~p"/api/recurring-tasks", %{"title" => "x", "recurrence" => "weekly"})
    assert %{"errors" => %{"day_of_week" => _}} = json_response(conn, 422)
  end
end
