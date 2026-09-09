defmodule ScheduledJobs.Runner do
  @moduledoc """
  Executes one job run as a plain OS process via `Port` — same
  Port-based streaming pattern as `MagicProxies.run/3` (not
  `System.cmd`, which buffers everything until exit): each output line
  is broadcast the moment it's produced, for the LiveView's live log
  panel, and also accumulated for the final run record.

  The timeout is enforced by wrapping the command with the `timeout(1)`
  coreutil rather than hand-rolling OS-pid signal delivery — simpler and
  more battle-tested than reimplementing process-group signalling, at
  the cost of only being best-effort against processes that escape their
  own process group.
  """

  require Logger

  alias ScheduledJobs.Job

  @doc """
  Fire-and-forget: inserts a `running` run row and executes the job
  under `ScheduledJobs.TaskSupervisor`. Returns as soon as the row is
  created — the caller (the tick hook, or a manual "run now") never
  waits on the job's actual duration.
  """
  def run_async(%Job{} = job, trigger) when trigger in ["scheduled", "manual"] do
    case ScheduledJobs.create_run(job, trigger) do
      {:ok, run} ->
        Task.Supervisor.start_child(ScheduledJobs.TaskSupervisor, fn -> execute(job, run) end)
        {:ok, run}

      {:error, _} = err ->
        err
    end
  end

  defp execute(job, run) do
    {output, exit_code} =
      case build_command(job) do
        :claude_not_found ->
          {"claude executable not found on PATH — cannot run prompt jobs", 127}

        {cmd, args} ->
          stream_cmd(cmd, args, run.id)
      end

    finish(job, run, status_for(exit_code), exit_code, output)
  rescue
    e ->
      Logger.error(
        "ScheduledJobs.Runner: job #{job.id} crashed: " <>
          Exception.format(:error, e, __STACKTRACE__)
      )

      finish(job, run, "failure", nil, "Runner crashed: #{Exception.message(e)}")
  end

  defp status_for(0), do: "success"
  defp status_for(_), do: "failure"

  defp finish(job, run, status, exit_code, output) do
    {inline_output, output_path} = maybe_spill(job.id, run.id, output)

    {:ok, finished} =
      ScheduledJobs.finish_run(run, %{
        status: status,
        exit_code: exit_code,
        output: inline_output,
        output_path: output_path
      })

    notify(job, finished)
  end

  # ── command construction ────────────────────────────────────────────────

  defp build_command(%Job{kind: "bash"} = job) do
    sh = System.find_executable("sh") || "/bin/sh"
    with_timeout(job, sh, ["-c", job.command])
  end

  defp build_command(%Job{kind: "prompt"} = job) do
    case System.find_executable("claude") do
      nil -> :claude_not_found
      claude -> with_timeout(job, claude, ["-p", job.command, "--dangerously-skip-permissions"])
    end
  end

  defp with_timeout(%Job{timeout_ms: ms}, cmd, args) do
    case System.find_executable("timeout") do
      nil ->
        {cmd, args}

      timeout_bin ->
        seconds = ms |> div(1000) |> max(1) |> Integer.to_string()
        {timeout_bin, ["--kill-after=10", "#{seconds}s", cmd | args]}
    end
  end

  # ── process streaming (Port, not System.cmd — see moduledoc) ───────────

  defp stream_cmd(cmd, args, run_id) do
    port =
      Port.open({:spawn_executable, cmd}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 8192},
        args: args
      ])

    collect_output(port, run_id, [])
  end

  defp collect_output(port, run_id, acc) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        SapoKit.PubSub.broadcast(ScheduledJobs.run_topic(run_id), {:job_log, run_id, line})
        collect_output(port, run_id, [line | acc])

      {^port, {:data, {:noeol, chunk}}} ->
        collect_output(port, run_id, [chunk | acc])

      {^port, {:exit_status, status}} ->
        {acc |> Enum.reverse() |> Enum.join("\n"), status}
    end
  end

  # ── output spill (large logs go to storage, not the DB row) ────────────

  defp maybe_spill(_job_id, run_id, output) do
    cap = SapoKit.ModuleConfig.get(:scheduled_jobs, :inline_output_cap_bytes) || 65_536

    if byte_size(output) > cap do
      rel_path = "runs/#{run_id}.log"
      File.write!(SapoKit.Storage.path(:scheduled_jobs, rel_path), output)
      truncated = binary_part(output, 0, cap) <> "\n\n… truncated, see #{rel_path}"
      {truncated, rel_path}
    else
      {output, nil}
    end
  rescue
    _ -> {output, nil}
  end

  # ── notification ─────────────────────────────────────────────────────────

  defp notify(%Job{notify_mode: "never"}, _run), do: :ok

  defp notify(%Job{notify_mode: "on_failure"} = job, %{status: "failure"} = run),
    do: do_notify(job, run)

  defp notify(%Job{notify_mode: "on_failure"}, _run), do: :ok

  defp notify(%Job{notify_mode: "always"} = job, run), do: do_notify(job, run)

  defp do_notify(job, run) do
    icon = if run.status == "success", do: "✅", else: "❌"
    exit_str = if run.exit_code, do: run.exit_code, else: "?"
    message = "#{icon} Scheduled job '#{job.name}' #{run.status} (exit #{exit_str})"

    # {:error, :no_destination} or any other failure is handled by the
    # facade's caller contract: log and move on, never crash the runner
    # over a notification that couldn't be delivered.
    case SapoKit.Notify.send(message, destination_id: job.notify_destination_id) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("ScheduledJobs.Runner: notify failed: #{inspect(reason)}")
    end
  end
end
