defmodule ProjectsWeb.Api.ProjectsController do
  @moduledoc false
  use SapoKit.Web, :controller

  def index(conn, _params) do
    json(conn, Enum.map(Projects.list_projects(), &serialize/1))
  end

  def create(conn, params) do
    attrs = %{"name" => params["name"], "github_url" => params["github_url"]}

    case Projects.create_and_setup(attrs) do
      {:ok, project} ->
        conn |> put_status(:created) |> json(serialize(project))

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_errors(conn, changeset)

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Setup failed: #{inspect(reason)}"})
    end
  end

  def show(conn, %{"id" => id}) do
    json(conn, serialize(Projects.get_project!(id)))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def delete(conn, %{"id" => id}) do
    project = Projects.get_project!(id)

    case Projects.delete_project_safely(project) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, reason} -> conn |> put_status(:conflict) |> json(%{error: reason})
    end
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  defp serialize(project) do
    %{
      id: project.id,
      name: project.name,
      github_url: project.github_url,
      position: project.position,
      last_pulled_at: project.last_pulled_at,
      params: Enum.map(project.params, &%{key: &1.key, value: &1.value}),
      inserted_at: project.inserted_at
    }
  end
end
