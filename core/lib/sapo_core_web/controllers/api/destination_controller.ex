defmodule SapoCoreWeb.Api.DestinationController do
  @moduledoc false
  use SapoCoreWeb, :controller

  import SapoKit.Web.ApiHelpers

  alias SapoCore.Notify

  def index(conn, _params) do
    json(conn, Enum.map(Notify.list_destinations(), &serialize/1))
  end

  def create(conn, params) do
    case Notify.create_destination(params) do
      {:ok, dest} ->
        conn
        |> put_status(:created)
        |> json(serialize(dest))

      {:error, changeset} ->
        render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Notify.get_destination(id) do
      nil ->
        render_not_found(conn)

      dest ->
        {:ok, _} = Notify.delete_destination(dest)
        send_resp(conn, :no_content, "")
    end
  end

  def set_default(conn, %{"id" => id}) do
    case Notify.get_destination(id) do
      nil ->
        render_not_found(conn)

      dest ->
        {:ok, dest} = Notify.set_default_destination(dest)
        json(conn, serialize(dest))
    end
  end

  defp serialize(dest) do
    %{
      id: dest.id,
      name: dest.name,
      channel: dest.channel,
      config: dest.config,
      is_default: dest.is_default,
      inserted_at: dest.inserted_at
    }
  end
end
