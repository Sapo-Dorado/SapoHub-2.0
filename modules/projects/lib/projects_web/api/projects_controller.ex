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

  # Named "sync" here (not "pull", despite calling Projects.pull_project/1)
  # because that's what it actually does — fetch, push anything local
  # that's ahead, then merge anything remote that's behind. Requires a
  # clean working tree first (see Git.check_clean/1); a caller with
  # uncommitted work-in-progress should use `push` below instead.
  def sync(conn, %{"id" => id}) do
    project = Projects.get_project!(id)

    case Projects.pull_project(project) do
      {:ok, updated} -> json(conn, serialize(updated))
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
    end
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  # Push-only: no clean-tree requirement, doesn't touch the working tree or
  # merge anything remote — just lands whatever's already committed
  # locally. See Git.push/1 for why this needs to exist separately from
  # `sync` above.
  def push(conn, %{"id" => id}) do
    project = Projects.get_project!(id)

    case Projects.push_project(project) do
      {:ok, output} -> json(conn, %{output: output})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
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
