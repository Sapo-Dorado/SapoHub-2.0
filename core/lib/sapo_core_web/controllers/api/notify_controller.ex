defmodule SapoCoreWeb.Api.NotifyController do
  @moduledoc false
  use SapoCoreWeb, :controller

  def create(conn, %{"message" => message} = params) do
    opts =
      []
      |> maybe_opt(:destination_id, params["destination_id"])
      |> maybe_opt(:image, params["image"])

    case SapoCore.Notify.send(message, opts) do
      :ok ->
        json(conn, %{status: "sent"})

      {:error, :no_destination} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no default notification destination configured"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "delivery failed: #{inspect(reason)}"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "message is required"})
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, value), do: [{key, value} | opts]
end
