defmodule SapoCore.Assistant.SessionNotifications do
  @moduledoc """
  In-memory store for per-session notification preferences (ported from v1).

  Each claude session gets `SAPO_SESSION_ID` in its environment; `sapo
  notify` forwards it, and the notify API consults this store to decide
  whether to deliver or suppress. Ephemeral by design.
  """

  use GenServer

  @table :assistant_session_notifications

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Enable or disable notifications for a session."
  def set_enabled(session_id, enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set, session_id, enabled})
  end

  @doc "Whether notifications are enabled for a session. Defaults to false."
  def enabled?(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, val}] -> val
      [] -> false
    end
  end

  @doc "Remove the preference entry (e.g. when a session ends)."
  def delete(session_id), do: GenServer.call(__MODULE__, {:delete, session_id})

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :protected, :named_table])
    {:ok, nil}
  end

  @impl true
  def handle_call({:set, session_id, enabled}, _from, state) do
    :ets.insert(@table, {session_id, enabled})
    {:reply, :ok, state}
  end

  def handle_call({:delete, session_id}, _from, state) do
    :ets.delete(@table, session_id)
    {:reply, :ok, state}
  end
end
