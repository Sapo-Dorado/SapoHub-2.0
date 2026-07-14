defmodule Reminders.Reminder do
  @moduledoc """
  A manual, user-created reminder (ported from v1 `SapoHub.Reminders.Reminder`).

  v1 also let other v1 modules create reminders on their behalf
  (`source_module`/`source_id`, used by MyPlate's due-date nudges). That
  cross-module coupling isn't allowed by the v2 module contract ("utilities
  are completely independent of each other") — any module that wants a
  timed nudge now calls `SapoKit.Scheduler` directly for its own data (see
  `modules/my_plate/lib/my_plate/due_reminder.ex`). This schema is scoped
  to what's left: reminders the user sets by hand on the Reminders page.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  @statuses ~w(pending sent cancelled failed)

  schema "reminders" do
    field :message, :string
    field :remind_at, :utc_datetime
    field :time_specific, :boolean, default: true
    field :status, :string, default: "pending"
    field :sent_at, :utc_datetime
    field :failure_reason, :string

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:message, :remind_at, :time_specific, :status, :sent_at, :failure_reason])
    |> validate_required([:message, :remind_at])
    |> validate_inclusion(:status, @statuses)
  end
end
