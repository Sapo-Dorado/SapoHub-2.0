defmodule SapoCore.Scheduler.Actions do
  @moduledoc """
  Persistence for one-shot scheduled actions (`core_scheduled_actions`),
  backing `SapoKit.Scheduler.schedule_at/4`.

  Rows are deleted when the handler returns `:ok`; otherwise they stay and
  the scheduler retries them on subsequent ticks. Anything with `at` in the
  past is due — including actions missed during downtime (catch-up).
  """

  use Ecto.Schema

  import Ecto.Query

  require Logger

  alias SapoCore.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "core_scheduled_actions" do
    field :at, :utc_datetime
    field :handler, :string
    field :payload, :map, default: %{}
    field :source, :string
    field :ref, :string

    timestamps(type: :utc_datetime)
  end

  # ── SapoKit.Scheduler impl (via SapoCore.Scheduler delegation) ─────────────

  def schedule_at(%DateTime{} = at, handler, payload, opts)
      when is_atom(handler) and is_map(payload) do
    source = Keyword.fetch!(opts, :source)
    ref = Keyword.fetch!(opts, :ref)

    %__MODULE__{
      at: DateTime.truncate(at, :second),
      handler: Atom.to_string(handler),
      payload: payload,
      source: to_string(source),
      ref: to_string(ref)
    }
    |> Repo.insert()
  end

  def cancel_scheduled(source, ref) do
    Repo.delete_all(by_source(source, ref))
    :ok
  end

  def reschedule(source, ref, %DateTime{} = new_at) do
    Repo.update_all(by_source(source, ref),
      set: [at: DateTime.truncate(new_at, :second)]
    )

    :ok
  end

  defp by_source(source, ref) do
    from a in __MODULE__, where: a.source == ^to_string(source) and a.ref == ^to_string(ref)
  end

  # ── Scheduler integration ──────────────────────────────────────────────────

  @doc "All actions due at `now` (at <= now), oldest first."
  def due(%DateTime{} = now) do
    Repo.all(from a in __MODULE__, where: a.at <= ^now, order_by: [asc: a.at])
  end

  @doc """
  Execute one action: resolve the handler and call `handle_scheduled/1`.
  Returns whatever the handler returns; unresolvable handlers are an error
  (kept for retry — typically a module was disabled; re-enabling it heals).
  """
  def execute(%__MODULE__{} = action) do
    case resolve_handler(action.handler) do
      {:ok, handler} ->
        handler.handle_scheduled(action.payload)

      {:error, reason} ->
        Logger.error(
          "scheduled action #{action.id}: cannot resolve handler " <>
            "#{action.handler}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc "Delete a completed action."
  def delete(%__MODULE__{} = action) do
    Repo.delete_all(from a in __MODULE__, where: a.id == ^action.id)
    :ok
  end

  defp resolve_handler(handler_string) do
    module = String.to_existing_atom(handler_string)

    if function_exported?(module, :handle_scheduled, 1) do
      {:ok, module}
    else
      {:error, :not_a_handler}
    end
  rescue
    ArgumentError -> {:error, :unknown_module}
  end
end
