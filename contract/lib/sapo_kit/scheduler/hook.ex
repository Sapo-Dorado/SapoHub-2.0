defmodule SapoKit.Scheduler.Hook do
  @moduledoc """
  Behaviour for hooking into SapoHub's core scheduler.

  The core scheduler ticks periodically (every ~60s), persists `last_run_at`
  per hook, and calls `run/1` whenever `next_run_at/2` is in the past. Runs
  never overlap for the same hook, and only a `:ok` return advances
  `last_run_at` — failures and crashes are retried on the next tick.

  ## Catch-up is YOUR responsibility

  If the hub was down (or a run kept failing), the scheduler does NOT replay
  every missed slot: once due, your hook is called ONCE, with the current
  time. `run/1` must therefore process the entire gap since the last
  successful run, not just "the current slot". Concretely:

    * derive missed work from your own data, not from how often you were
      called — e.g. a recurring-task hook should create instances for ALL
      periods between `last_run` and `now`, not just today's;
    * make `run/1` idempotent (dedupe on natural keys), since a run that
      fails after partial work will be retried in full;
    * remember `next_run_at/2` receives the last SUCCESSFUL run time (`nil`
      if never run) — return the earliest time work is due, and the
      scheduler's compare against `now` yields natural catch-up after
      downtime.

  Modules that need precise timing or long-lived processes should instead
  supply their own GenServer via `c:SapoKit.Module.children/1`.
  """

  @doc "Stable unique id for persistence, e.g. `\"my_plate.recurring\"`."
  @callback hook_id() :: String.t()

  @doc """
  When this hook should next run. Receives the persisted last successful run
  time (`nil` if never run) and the current time. Return `:never` to disable.
  """
  @callback next_run_at(last_run :: DateTime.t() | nil, now :: DateTime.t()) ::
              DateTime.t() | :never

  @doc """
  Execute the scheduled work. Called once when due — cover everything owed
  since the last successful run (see "Catch-up" above), idempotently.
  Return `:ok` to advance `last_run_at`; anything else (or a crash) leaves
  it unchanged so the whole run is retried on the next tick.
  """
  @callback run(now :: DateTime.t()) :: :ok | {:error, term()}
end
