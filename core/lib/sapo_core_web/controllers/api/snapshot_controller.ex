defmodule SapoCoreWeb.Api.SnapshotController do
  @moduledoc false
  use SapoCoreWeb, :controller

  import SapoKit.Web.ApiHelpers

  alias SapoCore.Snapshot

  def index(conn, _params) do
    json(conn, Enum.map(Snapshot.list(), &Map.take(&1, [:name, :size, :mtime])))
  end

  def create(conn, _params) do
    case Snapshot.save() do
      {:ok, path} ->
        conn
        |> put_status(:created)
        |> json(%{name: Path.basename(path), size: File.stat!(path).size})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "snapshot failed: #{inspect(reason)}"})
    end
  end

  def download(conn, %{"name" => name}) do
    case Snapshot.fetch(name) do
      {:ok, path} -> send_download(conn, {:file, path}, filename: name)
      {:error, :not_found} -> render_not_found(conn)
    end
  end
end
