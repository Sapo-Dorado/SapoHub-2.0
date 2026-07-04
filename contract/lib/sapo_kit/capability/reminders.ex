defmodule SapoKit.Capability.Reminders do
  @moduledoc """
  The `:reminders` capability contract.

  A module that provides scheduled user notifications implements this
  behaviour and declares `capabilities: [reminders: ImplModule]`. Consumer
  modules (e.g. MyPlate's due-date reminders) call the implementation via
  `SapoKit.Capabilities.get(:reminders)` and no-op when absent.

  Reminders created on behalf of another module carry a `source` (the
  consumer module id) and a `source_ref` (a consumer-scoped identifier such
  as a task id) so consumers can update or cancel what they created without
  tracking provider ids.
  """

  @type attrs :: %{
          required(:message) => String.t(),
          required(:remind_at) => DateTime.t(),
          required(:source) => atom(),
          required(:source_ref) => String.t()
        }

  @doc "Schedule a reminder. Idempotent per `{source, source_ref}` is provider-defined."
  @callback schedule(attrs()) :: {:ok, term()} | {:error, term()}

  @doc "Cancel all pending reminders created by `source` for `source_ref`."
  @callback cancel_by_source(source :: atom(), source_ref :: String.t()) :: :ok

  @doc "Reschedule/update pending reminders created by `source` for `source_ref`."
  @callback update_by_source(source :: atom(), source_ref :: String.t(), changes :: map()) ::
              :ok | {:error, term()}
end
