defmodule SapoCore.Assistant.TabStore do
  @moduledoc """
  In-memory store for assistant tab metadata (ported from v1).

  Persists tab session ids and labels across page reloads so users can
  reconnect to live claude sessions after navigating away. Intentionally
  ephemeral: lost on restart, which is fine since the sessions die too.

  Only extra tabs are stored — the default tab is always reconstructed by
  AssistantLive on mount.
  """

  use Agent

  @default_session_id "main"

  def default_session_id, do: @default_session_id

  def start_link(_opts) do
    Agent.start_link(fn -> %{tabs: [], next_num: 2} end, name: __MODULE__)
  end

  @doc "Stored extra tabs (excludes the default tab)."
  def list_tabs, do: Agent.get(__MODULE__, & &1.tabs)

  @doc "Next tab number for labelling."
  def next_num do
    Agent.get_and_update(__MODULE__, fn state ->
      {state.next_num, %{state | next_num: state.next_num + 1}}
    end)
  end

  @doc "Persist a new extra tab."
  def add_tab(session_id, label) do
    Agent.update(__MODULE__, fn state ->
      %{state | tabs: state.tabs ++ [%{session_id: session_id, label: label}]}
    end)
  end

  @doc "Remove a tab by session id (noop for the default tab)."
  def remove_tab(@default_session_id), do: :ok

  def remove_tab(session_id) do
    Agent.update(__MODULE__, fn state ->
      %{state | tabs: Enum.reject(state.tabs, &(&1.session_id == session_id))}
    end)
  end
end
