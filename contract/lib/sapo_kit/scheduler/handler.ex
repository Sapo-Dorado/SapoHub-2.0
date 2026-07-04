defmodule SapoKit.Scheduler.Handler do
  @moduledoc """
  Behaviour for one-shot scheduled action handlers
  (see `SapoKit.Scheduler.schedule_at/4`).

  The handler runs when the action is due — which may be LATER than the
  scheduled time if the hub was down (catch-up). Check the payload against
  current state and be idempotent:

    * the action may fire long after it was scheduled — decide whether the
      work still makes sense (e.g. don't remind about a completed task);
    * a handler that fails (non-`:ok` return or crash) is retried on the
      next tick, so partial work must be safe to redo.

  Returning `:ok` deletes the action; anything else keeps it for retry.
  Payload maps come back with STRING keys (JSON round-trip).
  """

  @callback handle_scheduled(payload :: %{String.t() => term()}) :: :ok | {:error, term()}
end
