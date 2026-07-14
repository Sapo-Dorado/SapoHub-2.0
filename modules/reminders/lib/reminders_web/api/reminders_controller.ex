defmodule RemindersWeb.Api.RemindersController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Reminders.Reminder

  def index(conn, params) do
    reminders =
      case params["status"] do
        "pending" -> Reminders.list_pending()
        "sent" -> Reminders.list_sent()
        "failed" -> Reminders.list_failed()
        _ -> Reminders.list_pending()
      end

    json(conn, Enum.map(reminders, &serialize/1))
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize(Reminders.get_reminder!(id)))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def create(conn, params) do
    case Reminders.create_reminder(params) do
      {:ok, reminder} -> conn |> put_status(:created) |> json(serialize(reminder))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Reminders.update_reminder(id, Map.delete(params, "id")) do
      {:ok, reminder} -> json(conn, serialize(reminder))
      {:error, :not_found} -> render_not_found(conn)
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def cancel(conn, %{"id" => id}) do
    case Reminders.cancel_reminder(id) do
      {:ok, reminder} -> json(conn, serialize(reminder))
      {:error, :not_found} -> render_not_found(conn)
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  defp serialize(%Reminder{} = r) do
    %{
      id: r.id,
      message: r.message,
      remind_at: r.remind_at,
      time_specific: r.time_specific,
      status: r.status,
      sent_at: r.sent_at,
      failure_reason: r.failure_reason,
      inserted_at: r.inserted_at
    }
  end
end
