defmodule MyPlate.RecurringTask do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  @valid_recurrences ~w(daily weekly monthly)

  schema "my_plate_recurring_tasks" do
    field :title, :string
    field :priority, :string, default: "medium"
    field :recurrence, :string
    field :day_of_week, :integer
    field :day_of_month, :integer
    field :create_ahead_days, :integer
    field :active, :boolean, default: true
    field :last_created_date, :date

    timestamps()
  end

  def changeset(recurring_task, attrs) do
    recurring_task
    |> cast(attrs, [
      :title,
      :priority,
      :recurrence,
      :day_of_week,
      :day_of_month,
      :create_ahead_days,
      :active,
      :last_created_date
    ])
    |> validate_required([:title, :priority, :recurrence])
    |> validate_inclusion(:recurrence, @valid_recurrences)
    |> validate_inclusion(:priority, ~w(high medium low))
    |> set_default_create_ahead()
    |> validate_recurrence_fields()
  end

  defp set_default_create_ahead(changeset) do
    if get_field(changeset, :create_ahead_days) do
      changeset
    else
      case get_field(changeset, :recurrence) do
        "daily" -> put_change(changeset, :create_ahead_days, 0)
        "weekly" -> put_change(changeset, :create_ahead_days, calculate_weekly_ahead(changeset))
        "monthly" -> put_change(changeset, :create_ahead_days, 7)
        _ -> changeset
      end
    end
  end

  defp calculate_weekly_ahead(changeset) do
    # Default: create on Monday of the week the task is due
    case get_field(changeset, :day_of_week) do
      dow when is_integer(dow) and dow > 1 -> dow - 1
      _ -> 0
    end
  end

  defp validate_recurrence_fields(changeset) do
    case get_field(changeset, :recurrence) do
      "weekly" ->
        changeset
        |> validate_required([:day_of_week])
        |> validate_inclusion(:day_of_week, 1..7)

      "monthly" ->
        changeset
        |> validate_required([:day_of_month])
        |> validate_inclusion(:day_of_month, 1..31)

      _ ->
        changeset
    end
  end

  @doc "Next due date strictly after `after_date` (v1 date math, verbatim)."
  def next_due_date(%__MODULE__{recurrence: "daily"}, after_date) do
    Date.add(after_date, 1)
  end

  def next_due_date(%__MODULE__{recurrence: "weekly", day_of_week: dow}, after_date) do
    current_dow = Date.day_of_week(after_date)
    days_ahead = rem(dow - current_dow + 7, 7)
    days_ahead = if days_ahead == 0, do: 7, else: days_ahead
    Date.add(after_date, days_ahead)
  end

  def next_due_date(%__MODULE__{recurrence: "monthly", day_of_month: dom}, after_date) do
    {year, month, _day} = Date.to_erl(after_date)

    case Date.new(year, month, min(dom, Date.days_in_month(Date.new!(year, month, 1)))) do
      {:ok, date} when is_struct(date, Date) ->
        if Date.compare(date, after_date) == :gt,
          do: date,
          else: next_month_date(year, month, dom)

      _ ->
        next_month_date(year, month, dom)
    end
  end

  defp next_month_date(year, month, dom) do
    {next_year, next_month} = if month == 12, do: {year + 1, 1}, else: {year, month + 1}
    max_day = Date.days_in_month(Date.new!(next_year, next_month, 1))
    Date.new!(next_year, next_month, min(dom, max_day))
  end
end
