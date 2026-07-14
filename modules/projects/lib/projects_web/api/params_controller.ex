defmodule ProjectsWeb.Api.ParamsController do
  @moduledoc false
  use SapoKit.Web, :controller

  def index(conn, %{"id" => id}) do
    Projects.get_project!(id)
    params = Projects.list_params(id)
    json(conn, Enum.map(params, &%{key: &1.key, value: &1.value}))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def upsert(conn, %{"id" => id, "key" => key} = params) do
    Projects.get_project!(id)
    value = params["value"] || ""

    case Projects.upsert_param(id, key, value) do
      {:ok, param} -> json(conn, %{key: param.key, value: param.value})
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def delete(conn, %{"id" => id, "key" => key}) do
    Projects.get_project!(id)
    Projects.delete_param(id, key)
    send_resp(conn, :no_content, "")
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end
end
