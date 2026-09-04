defmodule SapoCoreWeb.Api.SubscriptionsApiTest do
  @moduledoc """
  Exercises the subscriptions module's grouping/cost-per-month math
  end-to-end through core's router, since the module itself ships no
  test suite of its own (it can't stand up a DB in isolation — see
  `modules/recipes` for the same pattern).
  """
  use SapoCoreWeb.ConnCase, async: true

  test "groups by cadence and computes cost-per-month + totals", %{conn: conn} do
    conn =
      post(conn, "/api/subscriptions", %{
        name: "Netflix",
        cost: "15.49",
        interval_count: 1,
        interval_unit: "month"
      })

    assert %{"cost_per_month_cents" => 1549.0} = json_response(conn, 201)

    conn =
      post(build_conn(), "/api/subscriptions", %{
        name: "Amazon Prime",
        cost: "139.00",
        interval_count: 1,
        interval_unit: "year"
      })

    assert %{"cost_per_month_cents" => cost_per_month} = json_response(conn, 201)
    assert_in_delta cost_per_month, 139.00 / 12 * 100, 0.01

    conn = get(build_conn(), "/api/subscriptions")
    body = json_response(conn, 200)

    assert %{"groups" => groups, "total_monthly_cents" => total} = body
    assert length(groups) == 2

    # months-ascending before years-ascending
    assert [%{"interval_unit" => "month"}, %{"interval_unit" => "year"}] = groups

    assert_in_delta total, 1549.0 + 139.00 / 12 * 100, 0.01
  end

  test "validation errors return 422 with formatted errors", %{conn: conn} do
    conn = post(conn, "/api/subscriptions", %{})
    assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
  end

  test "cost must parse as a number", %{conn: conn} do
    conn = post(conn, "/api/subscriptions", %{name: "Bad", cost: "not-a-number"})
    assert %{"errors" => %{"cost" => _}} = json_response(conn, 422)
  end
end
