defmodule SapoKit.Scheduler do
  @moduledoc """
  Core scheduling facade for ONE-SHOT actions at a specific time.

  General-purpose: schedule any work for later — a notification, a cleanup,
  an export. The action is persisted; the core scheduler fires it when due
  by calling the handler (a `SapoKit.Scheduler.Handler`). Actions missed
  while the hub was down fire on the next tick after boot (catch-up), so
  handlers must be idempotent.

      SapoKit.Scheduler.schedule_at(
        remind_at,
        MyPlate.DueReminder,
        %{task_id: task.id},
        source: :my_plate,
        ref: task.id
      )

  `source` (your module id) + `ref` (your own identifier) let you cancel or
  reschedule what you created without tracking core ids:

      SapoKit.Scheduler.cancel_scheduled(:my_plate, task.id)
      SapoKit.Scheduler.reschedule(:my_plate, task.id, new_at)

  For RECURRING work, implement `SapoKit.Scheduler.Hook` instead.
  """

  @doc """
  Schedule `handler.handle_scheduled(payload)` to run at `at`.

  `payload` must be JSON-serializable; it is handed back to the handler
  with STRING keys. Scheduling again with the same `{source, ref}` adds a
  second action — use `reschedule/3` to move an existing one.
  """
  @spec schedule_at(DateTime.t(), module(), map(), source: atom(), ref: String.t()) ::
          {:ok, term()} | {:error, term()}
  def schedule_at(%DateTime{} = at, handler, payload, opts)
      when is_atom(handler) and is_map(payload) do
    impl().schedule_at(at, handler, payload, opts)
  end

  @doc "Cancel all pending actions created by `source` for `ref`."
  @spec cancel_scheduled(atom(), String.t() | term()) :: :ok
  def cancel_scheduled(source, ref) when is_atom(source) do
    impl().cancel_scheduled(source, ref)
  end

  @doc "Move all pending actions of `{source, ref}` to `new_at`."
  @spec reschedule(atom(), String.t() | term(), DateTime.t()) :: :ok
  def reschedule(source, ref, %DateTime{} = new_at) when is_atom(source) do
    impl().reschedule(source, ref, new_at)
  end

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :scheduler)
end
