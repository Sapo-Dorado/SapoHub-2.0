defmodule ScheduledJobsWeb.Live.Show do
  @moduledoc """
  One job's detail page: run history plus a live log tail while a run is
  in flight. Subscribes to the job-level topic for run list refreshes,
  and to the currently in-flight run's own topic
  (`ScheduledJobs.run_topic/1`) for streamed output lines — the same
  Port-per-line broadcast `ScheduledJobs.Runner` uses for its
  `MagicProxies`-style streaming.
  """
  use SapoKit.Web, :live_view

  alias ScheduledJobs.Cron

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    job = ScheduledJobs.get_job!(id)

    if connected?(socket), do: SapoKit.PubSub.subscribe(ScheduledJobs.topic())

    {:ok,
     socket
     |> assign(job: job, tail_run_id: nil, log_lines: [], expanded_run_id: nil)
     |> load_runs()}
  end

  defp load_runs(socket) do
    runs = ScheduledJobs.list_runs(socket.assigns.job.id)
    socket = assign(socket, runs: runs)

    case runs do
      [%{status: "running", id: id} | _] -> maybe_tail(socket, id)
      _ -> untail(socket)
    end
  end

  defp maybe_tail(socket, run_id) do
    if socket.assigns.tail_run_id == run_id do
      socket
    else
      if connected?(socket) do
        if socket.assigns.tail_run_id, do: SapoKit.PubSub.unsubscribe(ScheduledJobs.run_topic(socket.assigns.tail_run_id))
        SapoKit.PubSub.subscribe(ScheduledJobs.run_topic(run_id))
      end

      assign(socket, tail_run_id: run_id, log_lines: [])
    end
  end

  defp untail(socket) do
    if socket.assigns.tail_run_id do
      if connected?(socket), do: SapoKit.PubSub.unsubscribe(ScheduledJobs.run_topic(socket.assigns.tail_run_id))
      assign(socket, tail_run_id: nil, log_lines: [])
    else
      socket
    end
  end

  @impl true
  def handle_event("run_now", _params, socket) do
    {:ok, _run} = ScheduledJobs.Runner.run_async(socket.assigns.job, "manual")
    {:noreply, socket |> put_flash(:info, "Started '#{socket.assigns.job.name}'") |> load_runs()}
  end

  def handle_event("toggle_run", %{"id" => id}, socket) do
    expanded = if socket.assigns.expanded_run_id == id, do: nil, else: id
    {:noreply, assign(socket, expanded_run_id: expanded)}
  end

  @impl true
  def handle_info(:updated, socket) do
    job = ScheduledJobs.get_job!(socket.assigns.job.id)
    {:noreply, socket |> assign(job: job) |> load_runs()}
  end

  def handle_info({:job_log, run_id, line}, socket) do
    if run_id == socket.assigns.tail_run_id do
      lines = (socket.assigns.log_lines ++ [line]) |> Enum.take(-500)
      {:noreply, assign(socket, log_lines: lines)}
    else
      {:noreply, socket}
    end
  end

  defp describe_cron(cron_string) do
    case Cron.parse(cron_string) do
      {:ok, cron} -> Cron.describe(cron)
      {:error, _} -> cron_string
    end
  end

  defp duration(%{started_at: s, finished_at: f}) when not is_nil(f) do
    secs = DateTime.diff(f, s, :second)
    "#{secs}s"
  end

  defp duration(_run), do: "—"

  defp status_color("success"), do: "#7FB069"
  defp status_color("failure"), do: "#C1594A"
  defp status_color("running"), do: "#C9A227"
  defp status_color(_), do: "#86948F"

  defp local_time(dt), do: SapoKit.Time.format(dt, "%Y-%m-%d %H:%M:%S")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb={[{"scheduled jobs", "/scheduled-jobs"}, {@job.name, nil}]} items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[720px] mx-auto px-4 py-8 space-y-6">
        <div class="rounded-[4px] border border-[#242D31] bg-[#151B1E] px-4 py-3.5 flex items-center justify-between">
          <div>
            <p class="text-sm">{@job.name}</p>
            <p class="font-mono text-[10.5px] text-[#86948F] mt-0.5">
              {@job.kind} · {describe_cron(@job.cron)} · {if @job.enabled, do: "enabled", else: "disabled"}
            </p>
          </div>
          <button
            phx-click="run_now"
            class="px-3 py-[7px] rounded-[4px] border border-[#3C5934] bg-[#151B1E] font-mono text-[11.5px] text-[#7FB069] hover:bg-[#1B2420] cursor-pointer"
          >
            run now
          </button>
        </div>

        <div :if={@tail_run_id} class="rounded-[4px] border border-[#242D31] bg-[#0A0D0E] p-3">
          <p class="font-mono text-[10.5px] font-semibold uppercase tracking-[.14em] text-[#C9A227] mb-2">live — run in progress</p>
          <pre class="font-mono text-[11.5px] text-[#86948F] whitespace-pre-wrap max-h-[300px] overflow-y-auto">{Enum.join(@log_lines, "\n")}</pre>
        </div>

        <div class="flex items-center gap-2.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
          <span>run history</span>
          <span class="h-px flex-1 bg-[#242D31]"></span>
        </div>

        <p :if={@runs == []} class="text-[#86948F] text-sm">No runs yet.</p>

        <ul class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
          <li :for={run <- @runs}>
            <button
              phx-click="toggle_run"
              phx-value-id={run.id}
              class="w-full flex items-center gap-3 px-3 py-2.5 text-left cursor-pointer hover:bg-[#1B2420]"
            >
              <span class="font-mono text-[10.5px] shrink-0" style={"color: #{status_color(run.status)}"}>{run.status}</span>
              <span class="font-mono text-[11px] text-[#86948F] flex-1">{local_time(run.started_at)}</span>
              <span class="font-mono text-[10.5px] text-[#4A5458]">{run.trigger}</span>
              <span class="font-mono text-[10.5px] text-[#86948F] w-10 text-right">{duration(run)}</span>
              <span class="font-mono text-[10.5px] text-[#86948F] w-8 text-right">{run.exit_code}</span>
            </button>
            <div :if={@expanded_run_id == run.id} class="px-3 pb-3">
              <pre class="font-mono text-[11px] text-[#86948F] whitespace-pre-wrap max-h-[300px] overflow-y-auto bg-[#0A0D0E] rounded-[4px] p-2.5">{run.output || "(no output)"}</pre>
              <p :if={run.output_path} class="font-mono text-[10px] text-[#4A5458] mt-1">full log: {run.output_path}</p>
            </div>
          </li>
        </ul>
      </main>
    </div>
    """
  end
end
