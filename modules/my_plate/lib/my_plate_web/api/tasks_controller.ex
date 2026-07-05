defmodule MyPlateWeb.Api.TasksController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias MyPlate.Task

  def index(conn, params) do
    tasks =
      case params["priority"] do
        p when p in ["high", "medium", "low"] ->
          Enum.filter(MyPlate.list_active_tasks(), &(&1.priority == p))

        _ ->
          MyPlate.list_active_tasks()
      end

    json(conn, Enum.map(tasks, &serialize/1))
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize(MyPlate.get_task!(id)))
  end

  def create(conn, params) do
    case MyPlate.create_task(params) do
      {:ok, task} ->
        conn |> put_status(:created) |> json(serialize(task))

      {:error, changeset} ->
        render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    task = MyPlate.get_task!(id)

    case MyPlate.update_task(task, Map.delete(params, "id")) do
      {:ok, task} -> json(conn, serialize(task))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = MyPlate.delete_task(id)
    send_resp(conn, :no_content, "")
  end

  def complete(conn, %{"id" => id}) do
    {:ok, task} = MyPlate.complete_task(id)
    json(conn, serialize(task))
  end

  def uncomplete(conn, %{"id" => id}) do
    {:ok, task} = id |> MyPlate.get_task!() |> MyPlate.uncomplete_task()
    json(conn, serialize(task))
  end

  def reorder(conn, %{"id" => id, "priority" => priority, "position" => position}) do
    {:ok, task} = MyPlate.reorder_task(id, priority, position)
    json(conn, serialize(task))
  end

  defp serialize(%Task{} = t) do
    %{
      id: t.id,
      title: t.title,
      priority: t.priority,
      position: t.position,
      due_date: t.due_date,
      completed: t.completed,
      completed_at: t.completed_at,
      recurring_task_id: t.recurring_task_id,
      inserted_at: t.inserted_at
    }
  end
end
