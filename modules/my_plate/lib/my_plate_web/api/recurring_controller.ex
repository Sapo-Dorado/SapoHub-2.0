defmodule MyPlateWeb.Api.RecurringController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias MyPlate.RecurringTask

  def index(conn, _params) do
    json(conn, Enum.map(MyPlate.list_all_recurring_tasks(), &serialize/1))
  end

  def create(conn, params) do
    case MyPlate.create_recurring_task(params) do
      {:ok, rt} -> conn |> put_status(:created) |> json(serialize(rt))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    rt = MyPlate.get_recurring_task!(id)

    case MyPlate.update_recurring_task(rt, Map.delete(params, "id")) do
      {:ok, rt} -> json(conn, serialize(rt))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = MyPlate.delete_recurring_task(id)
    send_resp(conn, :no_content, "")
  end

  defp serialize(%RecurringTask{} = rt) do
    %{
      id: rt.id,
      title: rt.title,
      priority: rt.priority,
      recurrence: rt.recurrence,
      day_of_week: rt.day_of_week,
      day_of_month: rt.day_of_month,
      create_ahead_days: rt.create_ahead_days,
      active: rt.active,
      last_created_date: rt.last_created_date
    }
  end
end
