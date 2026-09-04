defmodule SubscriptionsWeb.Api.SubscriptionsController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Subscriptions.Subscription

  def index(conn, _params) do
    %{groups: groups, total_monthly_cents: total} = Subscriptions.grouped_summary()

    json(conn, %{
      groups: Enum.map(groups, &serialize_group/1),
      total_monthly_cents: total
    })
  end

  def create(conn, params) do
    case Subscriptions.create_subscription(params) do
      {:ok, subscription} -> conn |> put_status(:created) |> json(serialize(subscription))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.update_subscription(subscription, Map.delete(params, "id")) do
      {:ok, subscription} -> json(conn, serialize(subscription))
      {:error, changeset} -> render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = Subscriptions.delete_subscription(id)
    send_resp(conn, :no_content, "")
  end

  defp serialize_group(%{
         interval_unit: unit,
         interval_count: count,
         label: label,
         subscriptions: subscriptions,
         monthly_subtotal_cents: subtotal
       }) do
    %{
      interval_unit: unit,
      interval_count: count,
      label: label,
      monthly_subtotal_cents: subtotal,
      subscriptions: Enum.map(subscriptions, &serialize/1)
    }
  end

  defp serialize(%Subscription{} = s) do
    %{
      id: s.id,
      name: s.name,
      cost_cents: s.cost_cents,
      interval_unit: s.interval_unit,
      interval_count: s.interval_count,
      cost_per_month_cents: Subscription.cost_per_month_cents(s),
      notes: s.notes,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end
end
