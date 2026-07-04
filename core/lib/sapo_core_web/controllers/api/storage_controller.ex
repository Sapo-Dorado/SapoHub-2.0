defmodule SapoCoreWeb.Api.StorageController do
  @moduledoc false
  use SapoCoreWeb, :controller

  import SapoKit.Web.ApiHelpers

  alias SapoCore.Storage

  def index(conn, _params) do
    json(conn, Storage.list_files())
  end

  def show(conn, %{"path" => parts}) do
    api_path = Path.join(parts)

    with {:ok, abs} <- Storage.resolve(api_path),
         true <- File.regular?(abs) do
      send_download(conn, {:file, abs}, filename: Path.basename(abs))
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"path" => parts}) do
    case Storage.delete_file(Path.join(parts)) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, _} -> render_not_found(conn)
    end
  end
end
