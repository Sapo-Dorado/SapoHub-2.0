defmodule Projects.Runner do
  @moduledoc """
  Runs a single non-sudo script and streams its combined stdout/stderr live,
  broadcasting chunks over `SapoKit.PubSub` for `ProjectsWeb.Live.Show` to
  render — the same `{:script_output, runner_id, data}` /
  `{:script_done, runner_id, code}` shape v1's `ScriptRunner` used.

  v1 used a real PTY (ExPTY) so interactive/color output rendered nicely.
  There is no PTY facade in the module contract (and adding one would be
  new core scope for a cosmetic difference only) — an Erlang `Port` gives
  the same "stream stdout as it's produced" behavior without one; scripts
  that specifically require a real TTY are out of scope either way (v1's
  scripts are simple bash utilities, not interactive programs).
  """
  # `restart: :temporary`: a runner is a one-shot script execution, not a
  # service to keep alive. The default `:permanent` restart (from plain
  # `use GenServer`) would make the DynamicSupervisor relaunch — and thus
  # re-run the script — every time it exits `:normal` after finishing,
  # which is exactly what happened before this was set explicitly.
  use GenServer, restart: :temporary
  require Logger

  @doc "Starts a runner for a script under a project (identified by its DB id). Returns `{:ok, runner_id, pid}`."
  def start(project_id, script, project_root) do
    runner_id = generate_id()

    case Projects.RunnerSupervisor.start_child(
           runner_id: runner_id,
           project_id: project_id,
           script: script,
           project_root: project_root
         ) do
      {:ok, pid} -> {:ok, runner_id, pid}
      error -> error
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    send(self(), :start_script)

    {:ok,
     %{
       runner_id: opts[:runner_id],
       project_id: opts[:project_id],
       script: opts[:script],
       project_root: opts[:project_root],
       port: nil
     }}
  end

  @impl true
  def handle_info(:start_script, state) do
    script_with_params = state.script

    case Projects.ScriptCommand.build(script_with_params, state.project_root) do
      {:ok, {cmd, args, env, cwd}} ->
        port =
          Port.open({:spawn_executable, String.to_charlist(cmd)}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            :use_stdio,
            args: args,
            cd: cwd,
            env: Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
          ])

        {:noreply, %{state | port: port}}

      {:error, :sudo_unsupported} ->
        broadcast(state.runner_id, {:script_output, state.runner_id, "sudo scripts cannot be run from the Projects module.\n"})
        broadcast(state.runner_id, {:script_done, state.runner_id, 1})
        {:stop, :normal, state}

      {:error, reason} ->
        broadcast(state.runner_id, {:script_output, state.runner_id, "Error: #{inspect(reason)}\n"})
        broadcast(state.runner_id, {:script_done, state.runner_id, 1})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    broadcast(state.runner_id, {:script_output, state.runner_id, data})
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    broadcast(state.runner_id, {:script_done, state.runner_id, code})
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp broadcast(runner_id, message), do: SapoKit.PubSub.broadcast("projects:run:#{runner_id}", message)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
