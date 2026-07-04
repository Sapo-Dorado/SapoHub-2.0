defmodule SapoCore.Assistant.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for assistant PTY sessions: interactive claude sessions
  (`SessionRunner`) and fixed-command sessions (`CommandSession`), both
  registered in `SapoCore.Assistant.SessionRegistry`.
  """

  use DynamicSupervisor

  alias SapoCore.Assistant.CommandSession
  alias SapoCore.Assistant.SessionRunner

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start (or return the already-running) claude session."
  def start_session(session_id, opts \\ []) do
    opts = Keyword.merge([session_id: session_id], opts)

    case DynamicSupervisor.start_child(__MODULE__, {SessionRunner, opts}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc "Start (or return the already-running) fixed-command session."
  def start_command(session_id, cmd, args, opts \\ []) do
    opts = Keyword.merge([session_id: session_id, cmd: cmd, args: args], opts)

    case DynamicSupervisor.start_child(__MODULE__, {CommandSession, opts}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc "Stop the session (claude or command) registered under `session_id`."
  def stop_session(session_id) do
    case Registry.lookup(SapoCore.Assistant.SessionRegistry, session_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end
end
