defmodule SapoCoreWeb.Api.NotifyController do
  @moduledoc false
  use SapoCoreWeb, :controller

  def create(conn, %{"message" => message} = params) do
    opts =
      []
      |> maybe_opt(:destination_id, params["destination_id"])
      |> maybe_opt(:image, params["image"])

    # Per-session suppression: `sapo notify` inside a claude session carries
    # SAPO_SESSION_ID; the user toggles delivery per tab in the assistant UI.
    case params["session_id"] do
      nil ->
        deliver(conn, message, opts)

      sid ->
        if SapoCore.Assistant.SessionNotifications.enabled?(sid) do
          deliver(conn, message, opts)
        else
          json(conn, %{status: "suppressed"})
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "message is required"})
  end

  defp deliver(conn, message, opts) do
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

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, value), do: [{key, value} | opts]
end
