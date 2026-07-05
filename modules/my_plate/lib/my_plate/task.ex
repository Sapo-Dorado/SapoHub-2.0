defmodule MyPlate.Task do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  @priorities ~w(high medium low)

  schema "my_plate_tasks" do
    field :title, :string
    field :priority, :string, default: "medium"
    field :position, :integer
    field :due_date, :date
    field :completed, :boolean, default: false
    field :completed_at, :utc_datetime
    field :recurring_task_id, :binary_id

    timestamps()
  end

  def priorities, do: @priorities

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :priority,
      :position,
      :due_date,
      :completed,
      :completed_at,
      :recurring_task_id
    ])
    |> validate_required([:title, :priority])
    |> validate_inclusion(:priority, @priorities)
  end
end
