defmodule StorageWeb.Api.UploadController do
  @moduledoc """
  Manual file upload, used by both the LiveView upload panel and
  `sapo storage upload`. Multipart only — `Plug.Parsers` is already
  configured globally by core, so `%Plug.Upload{}` just shows up in params.
  """
  use SapoKit.Web, :controller

  def create(conn, %{"file" => %Plug.Upload{path: tmp, filename: filename}}) do
    case Storage.save_upload(tmp, filename) do
      {:ok, api_path} ->
        conn
        |> put_status(:created)
        |> json(%{path: api_path})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "expected a multipart 'file' field"})
  end
end
