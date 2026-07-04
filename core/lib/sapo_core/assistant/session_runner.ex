defmodule SapoCore.Assistant.SessionRunner do
  @moduledoc """
  GenServer managing one interactive `claude` session in a PTY.
  (Ported from v1 `SapoHub.Projects.SessionRunner`, keyed by session id
  instead of project id.)

  Registered in `SapoCore.Assistant.SessionRegistry` by session id. PTY
  output is broadcast on `"session:<id>"`; the last 512KB are buffered so
  reconnecting clients can replay. Input/resize arrive via cast; on PTY
  exit the code is broadcast and the server stops.
  """

  use GenServer, restart: :temporary

  require Logger

  alias SapoCore.Assistant
  alias SapoCore.Assistant.Terminal

  @buffer_limit 512_000

  def via(session_id), do: {:via, Registry, {SapoCore.Assistant.SessionRegistry, session_id}}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(opts[:session_id]))
  end

  # ── Public API ─────────────────────────────────────────────────────────────

  def send_input(session_id, data), do: GenServer.cast(via(session_id), {:input, data})

  def resize(session_id, cols, rows), do: GenServer.cast(via(session_id), {:resize, cols, rows})

  def alive?(session_id) do
    match?([{_pid, _}], Registry.lookup(SapoCore.Assistant.SessionRegistry, session_id))
  end

  @doc "Buffered output so reconnecting clients can replay the session."
  def get_buffer(session_id) do
    case Registry.lookup(SapoCore.Assistant.SessionRegistry, session_id) do
      [{pid, _}] -> GenServer.call(pid, :get_buffer)
      [] -> ""
    end
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    cols = if is_integer(opts[:cols]) and opts[:cols] > 0, do: opts[:cols], else: 220
    rows = if is_integer(opts[:rows]) and opts[:rows] > 0, do: opts[:rows], else: 50

    send(self(), :spawn_session)

    {:ok,
     %{
       session_id: session_id,
       pty_pid: nil,
       status: :starting,
       cols: cols,
       rows: rows,
       output_buffer: ""
     }}
  end

  @impl true
  def handle_info(:spawn_session, state) do
    claude_cmd = System.find_executable("claude") || "claude"

    args = ["--dangerously-skip-permissions"]

    args =
      if Application.get_env(:sapo_core, :assistant_chrome, false),
        do: args ++ ["--chrome"],
        else: args

    args =
      case Assistant.system_prompt() do
        "" -> args
        prompt -> args ++ ["--append-system-prompt", prompt]
      end

    case Terminal.spawn(claude_cmd, args,
           cwd: Assistant.workdir(),
           cols: state.cols,
           rows: state.rows,
           env: %{"SAPO_SESSION_ID" => state.session_id}
         ) do
      {:ok, pty_pid} ->
        Logger.info("SessionRunner: spawned PTY for session #{state.session_id}")
        {:noreply, %{state | pty_pid: pty_pid, status: :running}}

      {:error, reason} ->
        Logger.error(
          "SessionRunner: failed to spawn PTY for session #{state.session_id}: #{inspect(reason)}"
        )

        broadcast(state.session_id, {:session_exit, state.session_id, 1})
        {:stop, {:pty_spawn_failed, reason}, state}
    end
  end

  def handle_info({:pty_data, data}, state) do
    broadcast(state.session_id, {:session_output, state.session_id, data})
    buffer = trim_buffer(state.output_buffer <> data)
    {:noreply, %{state | output_buffer: buffer}}
  end

  def handle_info({:pty_exit, code}, state) do
    Logger.info("SessionRunner: PTY exited with code #{code} for session #{state.session_id}")
    broadcast(state.session_id, {:session_exit, state.session_id, code})
    {:stop, :normal, %{state | status: :exited, pty_pid: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_buffer, _from, state), do: {:reply, state.output_buffer, state}

  @impl true
  def handle_cast({:input, data}, state) do
    if state.pty_pid && state.status == :running, do: Terminal.write(state.pty_pid, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, state) do
    if state.pty_pid && state.status == :running, do: Terminal.resize(state.pty_pid, cols, rows)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.pty_pid && state.status == :running, do: Terminal.kill(state.pty_pid, 15)
    :ok
  end

  defp trim_buffer(buffer) when byte_size(buffer) > @buffer_limit do
    binary_part(buffer, byte_size(buffer) - @buffer_limit, @buffer_limit)
  end

  defp trim_buffer(buffer), do: buffer

  defp broadcast(session_id, message) do
    Phoenix.PubSub.broadcast(SapoCore.PubSub, "session:#{session_id}", message)
  end
end
