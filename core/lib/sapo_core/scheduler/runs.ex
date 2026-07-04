defmodule SapoCore.Scheduler.Runs do
  @moduledoc """
  Persistence for scheduler hook run times (`core_scheduler_runs`).

  One row per hook id holding the last SUCCESSFUL run time. Persisting only
  successes means failed/crashed runs are naturally retried on the next tick,
  and restarts pick up exactly where the last success left off (catch-up).
  """

  use Ecto.Schema

  import Ecto.Query

  alias SapoCore.Repo

  @primary_key {:hook_id, :string, autogenerate: false}
  schema "core_scheduler_runs" do
    field :last_run_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Last successful run time for `hook_id`, or `nil` if never run."
  @spec get_last_run(String.t()) :: DateTime.t() | nil
  def get_last_run(hook_id) when is_binary(hook_id) do
    Repo.one(from r in __MODULE__, where: r.hook_id == ^hook_id, select: r.last_run_at)
  end

  @doc "Record a successful run of `hook_id` at `at` (upsert)."
  @spec put_last_run(String.t(), DateTime.t()) :: :ok
  def put_last_run(hook_id, %DateTime{} = at) when is_binary(hook_id) do
    at = DateTime.truncate(at, :second)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%__MODULE__{hook_id: hook_id, last_run_at: at},
      on_conflict: [set: [last_run_at: at, updated_at: now]],
      conflict_target: :hook_id
    )

    :ok
  end
end
