defmodule Subscriptions do
  @moduledoc """
  Context for Subscriptions: CRUD on recurring subscriptions plus the
  cadence-grouped summary the LiveView and API index action both render
  from (`grouped_summary/0`) — kept in one place so the two views of the
  data can't drift apart.
  """

  import Ecto.Query

  alias SapoKit.Repo
  alias Subscriptions.Subscription

  def list_subscriptions do
    Subscription
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  def get_subscription!(id), do: Repo.get!(Subscription, id)

  def create_subscription(attrs) do
    with {:ok, subscription} <- %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert() do
      broadcast_updated()
      {:ok, subscription}
    end
  end

  def update_subscription(%Subscription{} = subscription, attrs) do
    with {:ok, subscription} <- subscription |> Subscription.changeset(attrs) |> Repo.update() do
      broadcast_updated()
      {:ok, subscription}
    end
  end

  def delete_subscription(%Subscription{} = subscription) do
    with {:ok, subscription} <- Repo.delete(subscription) do
      broadcast_updated()
      {:ok, subscription}
    end
  end

  def delete_subscription(id) when is_binary(id), do: id |> get_subscription!() |> delete_subscription()

  defp broadcast_updated, do: SapoKit.PubSub.broadcast("subscriptions:list", :updated)

  @doc "Grand total monthly cost across every subscription, in cents."
  def total_monthly_cents do
    list_subscriptions()
    |> Enum.reduce(0, fn s, acc -> acc + Subscription.cost_per_month_cents(s) end)
  end

  @doc """
  Subscriptions grouped by billing cadence (`interval_unit` +
  `interval_count`), sorted months-ascending then years-ascending. Each
  group carries its own monthly subtotal; the whole result carries the
  grand total — both derived from the same per-subscription cost/month
  figure so nothing can disagree with the parts it's made of.
  """
  def grouped_summary do
    groups =
      list_subscriptions()
      |> Enum.group_by(&{&1.interval_unit, &1.interval_count})
      |> Enum.map(fn {{unit, count}, subscriptions} ->
        monthly_subtotal_cents =
          Enum.reduce(subscriptions, 0, &(Subscription.cost_per_month_cents(&1) + &2))

        %{
          interval_unit: unit,
          interval_count: count,
          label: cadence_label(unit, count),
          subscriptions: subscriptions,
          monthly_subtotal_cents: monthly_subtotal_cents
        }
      end)
      |> Enum.sort_by(fn %{interval_unit: unit, interval_count: count} -> {unit_rank(unit), count} end)

    total_monthly_cents = Enum.reduce(groups, 0, &(&1.monthly_subtotal_cents + &2))

    %{groups: groups, total_monthly_cents: total_monthly_cents}
  end

  defp unit_rank("month"), do: 0
  defp unit_rank("year"), do: 1

  defp cadence_label(unit, 1), do: "every #{unit}"
  defp cadence_label(unit, count), do: "every #{count} #{unit}s"
end
