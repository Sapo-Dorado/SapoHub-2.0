defmodule SapoKit.Scheduler.Hook do
  @moduledoc """
  Behaviour for hooking into SapoHub's core scheduler.

  The core scheduler ticks periodically (every ~60s), persists `last_run_at`
  per hook, and calls `run/1` whenever `next_run_at/2` is in the past —
  which yields natural catch-up after downtime. Runs never overlap for the
  same hook.

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

  @doc "Execute the scheduled work."
  @callback run(now :: DateTime.t()) :: :ok | {:error, term()}
end
