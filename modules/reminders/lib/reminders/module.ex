defmodule Reminders.Module do
  @moduledoc """
  SapoKit.Module implementation for Reminders — one-off, user-set nudges
  delivered via `SapoKit.Notify` at a chosen time (ported from v1
  `SapoHub.Reminders`).

  Delivery goes through core's one-shot scheduler (`SapoKit.Scheduler`),
  same pattern as `MyPlate.DueReminder` — no `scheduler_hooks/0` or
  `children/1` needed, each reminder just schedules its own action.
  """
  use SapoKit.Module

  @impl true
  def id, do: :reminders

  @impl true
  def title, do: "Reminders"

  @impl true
  def icon, do: "hero-bell"

  @impl true
  def statusline_items(_config) do
    [
      %SapoKit.StatuslineItem{
        id: "reminders.pending",
        label: "Reminders pending",
        text: fn ->
          case Reminders.count_pending() do
            0 -> "0 pending"
            n -> "#{n} pending"
          end
        end,
        level: :neutral,
        topics: ["reminders:updates"]
      }
    ]
  end

  @impl true
  def ui_routes do
    [%{path: "/reminders", live_view: RemindersWeb.Live.Index, action: :index}]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/reminders", controller: RemindersWeb.Api.RemindersController, action: :index},
      %{verb: :post, path: "/reminders", controller: RemindersWeb.Api.RemindersController, action: :create},
      %{verb: :get, path: "/reminders/:id", controller: RemindersWeb.Api.RemindersController, action: :show},
      %{verb: :patch, path: "/reminders/:id", controller: RemindersWeb.Api.RemindersController, action: :update},
      %{verb: :delete, path: "/reminders/:id", controller: RemindersWeb.Api.RemindersController, action: :cancel}
    ]
  end

  @impl true
  def ai_context do
    """
    Reminders lets the user set one-off nudges delivered through their
    configured notification destination at a chosen time. Pending: \
    #{Reminders.count_pending()}.
    Statuses: pending, sent, cancelled, failed. Use the /api/reminders
    endpoints (GET list w/ optional ?status=, POST create
    {message, remind_at, time_specific}, PATCH update, DELETE cancel).
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    If the user asks to be reminded of something, create a Reminders entry
    (POST /api/reminders) rather than tracking it yourself.
    """
  end

  @impl true
  def config_schema do
    [
      default_remind_time: [type: :string, default: "09:00"],
      timezone: [type: :string, default: "Etc/UTC"]
    ]
  end
end
