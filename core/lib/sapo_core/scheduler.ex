defmodule SapoCore.Scheduler do
  @moduledoc """
  The ONE core scheduler. Drives two kinds of work from a single ~60s tick
  (first tick immediately at boot):

    * RECURRING hooks (`SapoKit.Scheduler.Hook`): per-hook `last_run_at`
      persisted in `core_scheduler_runs`; due when `next_run_at(last, now)`
      is in the past — natural catch-up after downtime.
    * ONE-SHOT scheduled actions (`SapoKit.Scheduler.schedule_at/4`):
      persisted in `core_scheduled_actions`; due when `at <= now`; deleted
      when the handler returns `:ok`, otherwise retried next tick.

  Work runs under `SapoCore.TaskSupervisor`. Neither a hook nor an action
  ever overlaps itself (running-set guard). Only success advances/clears
  persisted state, so failures and crashes retry.

  Options (all injectable for tests):

    * `:hooks` — list of hook modules (default: collected from the registry
      by `SapoCore.Application`)
    * `:actions` — whether to fire one-shot actions (default `true`)
    * `:tick_ms` — tick interval, or `:manual` to only tick via `tick/1`
    * `:now_fun` — clock, defaults to `&DateTime.utc_now/0`
    * `:task_supervisor` — defaults to `SapoCore.TaskSupervisor`
    * `:name` — process name; pass `nil` for an anonymous server
  """

  use GenServer

  require Logger

  alias SapoCore.Scheduler.Actions
  alias SapoCore.Scheduler.Runs

  @default_tick_ms 60_000

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  # ── SapoKit.Scheduler impl (one-shot actions) ──────────────────────────────

  defdelegate schedule_at(at, handler, payload, opts), to: Actions
  defdelegate cancel_scheduled(source, ref), to: Actions
  defdelegate reschedule(source, ref, new_at), to: Actions

  # ── Introspection / test API ───────────────────────────────────────────────

  @doc "Ids currently executing (hook ids and `\"action:<id>\"`)."
  @spec running(GenServer.server()) :: [String.t()]
  def running(server \\ __MODULE__), do: GenServer.call(server, :running)

  @doc "Trigger a tick now (used by tests together with `tick_ms: :manual`)."
  def tick(server \\ __MODULE__), do: send(server, :tick)

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      hooks: Keyword.get(opts, :hooks, []),
      actions: Keyword.get(opts, :actions, true),
      tick_ms: Keyword.get(opts, :tick_ms, @default_tick_ms),
      now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
      task_sup: Keyword.get(opts, :task_supervisor, SapoCore.TaskSupervisor),
      # ref => {:hook, hook_id, run_time} | {:action, %Actions{}}
      running: %{}
    }

    schedule_tick(state, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:running, _from, state) do
    {:reply, Enum.map(Map.values(state.running), &running_id/1), state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.now_fun.()

    state =
      state
      |> tick_hooks(now)
      |> tick_actions(now)

    schedule_tick(state, state.tick_ms)
    {:noreply, state}
  end

  # Task completed normally.
  def handle_info({ref, result}, state) when is_map_key(state.running, ref) do
    Process.demonitor(ref, [:flush])
    {entry, running} = Map.pop(state.running, ref)
    complete(entry, result)
    {:noreply, %{state | running: running}}
  end

  # Task crashed.
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.running, ref) do
    {entry, running} = Map.pop(state.running, ref)
    Logger.error("scheduler #{running_id(entry)} crashed: #{inspect(reason)}")
    {:noreply, %{state | running: running}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Hooks ──────────────────────────────────────────────────────────────────

  defp tick_hooks(state, now) do
    running_ids = MapSet.new(Map.values(state.running), &running_id/1)

    Enum.reduce(state.hooks, state, fn hook, acc ->
      hook_id = hook.hook_id()

      cond do
        MapSet.member?(running_ids, hook_id) ->
          acc

        hook_due?(hook, hook_id, now) ->
          start_task(acc, {:hook, hook_id, now}, fn -> hook.run(now) end)

        true ->
          acc
      end
    end)
  end

  defp hook_due?(hook, hook_id, now) do
    last = Runs.get_last_run(hook_id)

    case hook.next_run_at(last, now) do
      :never -> false
      %DateTime{} = at -> DateTime.compare(at, now) != :gt
    end
  end

  # ── One-shot actions ───────────────────────────────────────────────────────

  defp tick_actions(%{actions: false} = state, _now), do: state

  defp tick_actions(state, now) do
    running_ids = MapSet.new(Map.values(state.running), &running_id/1)

    Enum.reduce(Actions.due(now), state, fn action, acc ->
      entry = {:action, action}

      if MapSet.member?(running_ids, running_id(entry)) do
        acc
      else
        start_task(acc, entry, fn -> Actions.execute(action) end)
      end
    end)
  end

  # ── Shared ─────────────────────────────────────────────────────────────────

  defp start_task(state, entry, fun) do
    task = Task.Supervisor.async_nolink(state.task_sup, fun)
    %{state | running: Map.put(state.running, task.ref, entry)}
  end

  defp complete({:hook, hook_id, run_time}, :ok), do: Runs.put_last_run(hook_id, run_time)

  defp complete({:hook, hook_id, _run_time}, other) do
    Logger.warning(
      "scheduler hook #{hook_id} returned #{inspect(other)}; " <>
        "last_run_at not advanced"
    )
  end

  defp complete({:action, action}, :ok), do: Actions.delete(action)

  defp complete({:action, action}, other) do
    Logger.warning(
      "scheduled action #{action.id} (#{action.source}/#{action.ref}) " <>
        "returned #{inspect(other)}; kept for retry"
    )
  end

  defp running_id({:hook, hook_id, _run_time}), do: hook_id
  defp running_id({:action, action}), do: "action:#{action.id}"

  defp schedule_tick(%{tick_ms: :manual}, _ms), do: :ok
  defp schedule_tick(_state, ms), do: Process.send_after(self(), :tick, ms)
end
