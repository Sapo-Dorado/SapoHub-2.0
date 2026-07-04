defmodule SapoCore.Assistant.CommandSession do
  @moduledoc """
  GenServer running ONE fixed command in a PTY (e.g. the Deploy button's
  `sudo sapohub-deploy`). Same streaming/replay model as `SessionRunner` —
  output broadcast on `"session:<id>"`, 512KB replay buffer — but the
  command is fixed at start (no arbitrary input; interactive input is still
  forwarded so the user can answer prompts) and the terminal is read-mostly.

  Registered under the same `SessionRegistry` as claude sessions, so ids
  must not collide (use e.g. `"deploy"`).
  """

  use GenServer, restart: :temporary

  require Logger

  alias SapoCore.Assistant.Terminal

  @buffer_limit 512_000

  def via(session_id), do: {:via, Registry, {SapoCore.Assistant.SessionRegistry, session_id}}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(opts[:session_id]))
  end

  def send_input(session_id, data), do: GenServer.cast(via(session_id), {:input, data})
  def resize(session_id, cols, rows), do: GenServer.cast(via(session_id), {:resize, cols, rows})

  def alive?(session_id) do
    match?([{_pid, _}], Registry.lookup(SapoCore.Assistant.SessionRegistry, session_id))
  end

  def get_buffer(session_id) do
    case Registry.lookup(SapoCore.Assistant.SessionRegistry, session_id) do
      [{pid, _}] -> GenServer.call(pid, :get_buffer)
      [] -> ""
    end
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      session_id: Keyword.fetch!(opts, :session_id),
      cmd: Keyword.fetch!(opts, :cmd),
      args: Keyword.get(opts, :args, []),
      cwd: Keyword.get(opts, :cwd),
      env: Keyword.get(opts, :env, %{}),
      cols: Keyword.get(opts, :cols, 220),
      rows: Keyword.get(opts, :rows, 50),
      pty_pid: nil,
      status: :starting,
      output_buffer: ""
    }

    send(self(), :spawn_command)
    {:ok, state}
  end

  @impl true
  def handle_info(:spawn_command, state) do
    case Terminal.spawn(state.cmd, state.args,
           cwd: state.cwd,
           cols: state.cols,
           rows: state.rows,
           env: state.env
         ) do
      {:ok, pty_pid} ->
        Logger.info("CommandSession #{state.session_id}: spawned #{state.cmd}")
        {:noreply, %{state | pty_pid: pty_pid, status: :running}}

      {:error, reason} ->
        Logger.error("CommandSession #{state.session_id}: spawn failed: #{inspect(reason)}")
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
    Logger.info("CommandSession #{state.session_id}: exited with #{code}")
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
