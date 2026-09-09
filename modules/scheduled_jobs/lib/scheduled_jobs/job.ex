defmodule ScheduledJobs.Job do
  @moduledoc """
  A user-defined job: either a bash command or an assistant prompt
  ("run a skill" — invoked headlessly as `claude -p`, see
  `ScheduledJobs.Runner`), fired on a cron schedule.
  """
  use SapoKit.Schema

  import Ecto.Changeset

  alias ScheduledJobs.Cron

  @kinds ~w(bash prompt)
  @notify_modes ~w(always on_failure never)

  schema "scheduled_jobs_jobs" do
    field :name, :string
    field :kind, :string
    field :command, :string
    field :cron, :string
    field :enabled, :boolean, default: true
    field :notify_mode, :string, default: "on_failure"
    field :notify_destination_id, :binary_id
    field :timeout_ms, :integer
    field :last_checked_minute, :utc_datetime

    timestamps()
  end

  def kinds, do: @kinds
  def notify_modes, do: @notify_modes

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :name,
      :kind,
      :command,
      :cron,
      :enabled,
      :notify_mode,
      :notify_destination_id,
      :timeout_ms
    ])
    |> put_default_timeout()
    |> validate_required([:name, :kind, :command, :cron, :timeout_ms])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:notify_mode, @notify_modes)
    |> validate_number(:timeout_ms, greater_than: 0)
    |> validate_cron()
  end

  defp put_default_timeout(changeset) do
    case get_field(changeset, :timeout_ms) do
      nil -> put_change(changeset, :timeout_ms, default_timeout_ms())
      _ -> changeset
    end
  end

  defp default_timeout_ms do
    SapoKit.ModuleConfig.get(:scheduled_jobs, :default_timeout_ms) || 1_800_000
  end

  @doc false
  def checked_minute_changeset(job, %DateTime{} = minute) do
    change(job, last_checked_minute: minute)
  end

  defp validate_cron(changeset) do
    validate_change(changeset, :cron, fn :cron, expr ->
      case Cron.parse(expr) do
        {:ok, _} -> []
        {:error, reason} -> [cron: reason]
      end
    end)
  end
end
