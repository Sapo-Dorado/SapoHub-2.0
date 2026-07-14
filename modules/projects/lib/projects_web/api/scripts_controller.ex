defmodule ProjectsWeb.Api.ScriptsController do
  @moduledoc false
  use SapoKit.Web, :controller

  def index(conn, %{"id" => id}) do
    project = Projects.get_project!(id)
    scripts = project |> Projects.list_runnable_scripts() |> Enum.map(&%{name: &1.name, file: &1.file})
    json(conn, scripts)
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def run(conn, %{"id" => id} = params) do
    project = Projects.get_project!(id)
    script_file = params["script_file"]
    extra_params = params["params"] || %{}
    timeout_ms = (params["timeout_seconds"] || 120) * 1000

    if is_binary(script_file) and String.contains?(script_file, "..") do
      conn |> put_status(:bad_request) |> json(%{error: "invalid script path"})
    else
      case Enum.find(Projects.list_scripts(project), &(&1.file == script_file)) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "script not found"})

        %{sudo: true} ->
          conn |> put_status(:forbidden) |> json(%{error: "sudo scripts cannot be run via the API"})

        script ->
          case Projects.run_script_blocking(project, script, extra_params, timeout_ms) do
            {:ok, %{output: output, exit_code: exit_code, duration_ms: duration_ms}} ->
              json(conn, %{exit_code: exit_code, output: output, duration_ms: duration_ms})

            {:error, :timeout} ->
              conn |> put_status(408) |> json(%{error: "script timed out"})

            {:error, reason} ->
              conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
          end
      end
    end
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end
end
