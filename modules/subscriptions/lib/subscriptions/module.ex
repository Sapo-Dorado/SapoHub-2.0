defmodule Subscriptions.Module do
  @moduledoc """
  SapoKit.Module implementation for Subscriptions: recurring subscriptions
  grouped by billing cadence, with per-item and grand-total monthly cost.
  See `docs/module-authoring.md` and `Subscriptions` (the context) for the
  full design.
  """
  use SapoKit.Module

  @impl true
  def id, do: :subscriptions

  @impl true
  def title, do: "Subscriptions"

  @impl true
  def icon, do: "hero-banknotes"

  @impl true
  def statusline_items(_config) do
    [
      %SapoKit.StatuslineItem{
        id: "subscriptions.monthly_total",
        label: "Subscriptions",
        text: fn -> "#{money(Subscriptions.total_monthly_cents())}/mo" end,
        level: :neutral,
        topics: ["subscriptions:list"]
      }
    ]
  end

  @impl true
  def ui_routes do
    [%{path: "/subscriptions", live_view: SubscriptionsWeb.Live.Index, action: :index}]
  end

  @impl true
  def api_routes do
    alias SubscriptionsWeb.Api.SubscriptionsController, as: C

    [
      %{verb: :get, path: "/subscriptions", controller: C, action: :index},
      %{verb: :post, path: "/subscriptions", controller: C, action: :create},
      %{verb: :patch, path: "/subscriptions/:id", controller: C, action: :update},
      %{verb: :delete, path: "/subscriptions/:id", controller: C, action: :delete}
    ]
  end

  @impl true
  def ai_context do
    %{groups: groups, total_monthly_cents: total} = Subscriptions.grouped_summary()
    count = Subscriptions.list_subscriptions() |> length()

    """
    Subscriptions tracks recurring subscriptions billed every X months or
    every X years, grouped by billing cadence. #{count} subscription(s)
    across #{length(groups)} cadence group(s); current total monthly cost:
    #{money(total)}.

    Cost is stored in cents (`cost_cents`); the API/CLI accept a dollar
    string for cost (e.g. "9.99") and it's parsed to cents. Cadence is
    `interval_unit` ("month" | "year") + `interval_count` (>= 1) — e.g.
    "every 3 months" is unit "month", count 3; "every 1 year" is unit
    "year", count 1. A subscription's monthly-equivalent cost is
    cost_cents / interval_count (month) or cost_cents / (interval_count *
    12) (year).

    Use `sapo subscriptions list|create|edit|delete` or the
    /api/subscriptions endpoints.
    """
  end

  defp money(cents), do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
end
