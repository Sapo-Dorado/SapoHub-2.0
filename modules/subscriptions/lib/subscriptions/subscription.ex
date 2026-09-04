defmodule Subscriptions.Subscription do
  @moduledoc """
  A recurring subscription billed every `interval_count` `interval_unit`s
  (`"month"` or `"year"`). `cost_cents` is the amount charged per billing
  cycle, not per month — use `cost_per_month_cents/1` for the normalized
  figure grouping/totals are built from.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  @units ["month", "year"]

  schema "subscriptions_subscriptions" do
    field :name, :string
    field :cost_cents, :integer
    # Write-only convenience: accepts a dollar string ("9.99") from the
    # API/CLI and gets converted into cost_cents by the changeset — never
    # persisted itself.
    field :cost, :string, virtual: true
    field :interval_unit, :string
    field :interval_count, :integer, default: 1
    field :notes, :string, default: ""

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:name, :cost, :cost_cents, :interval_unit, :interval_count, :notes])
    |> update_change(:name, &String.trim/1)
    |> parse_cost()
    |> validate_required([:name, :cost_cents, :interval_unit, :interval_count])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:interval_unit, @units)
    |> validate_number(:cost_cents, greater_than: 0)
    |> validate_number(:interval_count, greater_than: 0)
  end

  defp parse_cost(changeset) do
    case get_change(changeset, :cost) do
      nil ->
        changeset

      cost_str ->
        case Float.parse(String.trim(cost_str)) do
          {dollars, ""} -> put_change(changeset, :cost_cents, round(dollars * 100))
          _ -> add_error(changeset, :cost, "must be a number like 9.99")
        end
    end
  end

  @doc "Cost normalized to a monthly rate, in cents (may be fractional)."
  def cost_per_month_cents(%__MODULE__{interval_unit: "month", interval_count: n, cost_cents: cents}) do
    cents / n
  end

  def cost_per_month_cents(%__MODULE__{interval_unit: "year", interval_count: n, cost_cents: cents}) do
    cents / (n * 12)
  end
end
