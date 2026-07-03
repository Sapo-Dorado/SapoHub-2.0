defmodule SapoKit.Web.ApiHelpers do
  @moduledoc """
  Shared helpers for module API controllers.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc "Formats changeset errors as a `%{field => [message]}` map."
  def format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc "Renders a 422 with formatted changeset errors."
  def render_changeset_errors(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: format_errors(changeset)})
  end

  @doc "Renders a 404."
  def render_not_found(conn, message \\ "not found") do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end
end
