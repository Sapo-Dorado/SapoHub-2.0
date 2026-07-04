defmodule SapoCore.Scheduler do
  @moduledoc """
  The ONE core scheduler for periodic module work.

  Ticks every 60s (first tick immediately at boot). On each tick it asks
  every registered `SapoKit.Scheduler.Hook` when it should next run, given
  the persisted last successful run time — so hooks catch up naturally after
  downtime. Due hooks run under `SapoCore.TaskSupervisor`; a hook never
  overlaps itself (running-set guard); only a `:ok` result advances
  `last_run_at`, so failures and crashes retry on the next tick.

  Options (all injectable for tests):

    * `:hooks` — list of hook modules (default: collected from the registry
      by `SapoCore.Application`)
    * `:tick_ms` — tick interval, or `:manual` to only tick via `tick/1`
    * `:now_fun` — clock, defaults to `&DateTime.utc_now/0`
    * `:task_supervisor` — defaults to `SapoCore.TaskSupervisor`
    * `:name` — process name; pass `nil` for an anonymous server
  """

  use GenServer

  require Logger

  alias SapoCore.Scheduler.Runs

  @default_tick_ms 60_000

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Hook ids currently executing."
  @spec running(GenServer.server()) :: [String.t()]
  def running(server \\ __MODULE__), do: GenServer.call(server, :running)

  @doc "Trigger a tick now (used by tests together with `tick_ms: :manual`)."
  def tick(server \\ __MODULE__), do: send(server, :tick)

  @impl true
  def init(opts) do
    state = %{
      hooks: Keyword.get(opts, :hooks, []),
      tick_ms: Keyword.get(opts, :tick_ms, @default_tick_ms),
      now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
      task_sup: Keyword.get(opts, :task_supervisor, SapoCore.TaskSupervisor),
      # ref => {hook_id, run_time}
      running: %{}
    }

    schedule_tick(state, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:running, _from, state) do
    {:reply, Enum.map(Map.values(state.running), &elem(&1, 0)), state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = state.now_fun.()
    running_ids = MapSet.new(Map.values(state.running), &elem(&1, 0))

    state =
      Enum.reduce(state.hooks, state, fn hook, acc ->
        hook_id = hook.hook_id()

        cond do
          MapSet.member?(running_ids, hook_id) -> acc
          due?(hook, hook_id, now) -> start_run(acc, hook, hook_id, now)
          true -> acc
        end
      end)

    schedule_tick(state, state.tick_ms)
    {:noreply, state}
  end

  # Task completed normally.
  def handle_info({ref, result}, state) when is_map_key(state.running, ref) do
    Process.demonitor(ref, [:flush])
    {{hook_id, run_time}, running} = Map.pop(state.running, ref)

    case result do
      :ok ->
        Runs.put_last_run(hook_id, run_time)

      other ->
        Logger.warning(
          "scheduler hook #{hook_id} returned #{inspect(other)}; last_run_at not advanced"
        )
    end

    {:noreply, %{state | running: running}}
  end

  # Task crashed.
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.running, ref) do
    {{hook_id, _run_time}, running} = Map.pop(state.running, ref)
    Logger.error("scheduler hook #{hook_id} crashed: #{inspect(reason)}")
    {:noreply, %{state | running: running}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp due?(hook, hook_id, now) do
    last = Runs.get_last_run(hook_id)

    case hook.next_run_at(last, now) do
      :never -> false
      %DateTime{} = at -> DateTime.compare(at, now) != :gt
    end
  end

  defp start_run(state, hook, hook_id, now) do
    task = Task.Supervisor.async_nolink(state.task_sup, fn -> hook.run(now) end)
    %{state | running: Map.put(state.running, task.ref, {hook_id, now})}
  end

  defp schedule_tick(%{tick_ms: :manual}, _ms), do: :ok
  defp schedule_tick(_state, ms), do: Process.send_after(self(), :tick, ms)
end
