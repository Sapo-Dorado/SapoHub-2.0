defmodule ScheduledJobsWeb.Live.Index do
  @moduledoc """
  Job list + create/edit form (modal, matching the subscriptions module's
  pattern). The schedule is authored through a small preset builder
  (every N minutes/hours, daily at HH:MM, weekly on days at HH:MM, or a
  raw cron expression under "custom") — `ScheduledJobs.Cron.Builder`
  translates the preset to/from the canonical cron string stored on the
  job, so the UI never requires the user to know cron syntax unless they
  opt into "custom".
  """
  use SapoKit.Web, :live_view

  alias ScheduledJobs.Cron.Builder
  alias ScheduledJobs.Job

  @weekday_labels %{0 => "Sun", 1 => "Mon", 2 => "Tue", 3 => "Wed", 4 => "Thu", 5 => "Fri", 6 => "Sat"}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe(ScheduledJobs.topic())

    {:ok,
     socket
     |> assign(
       job_editing: nil,
       job_form: nil,
       job_form_error: nil,
       form_key: 0,
       confirm_delete: nil
     )
     |> load()}
  end

  defp load(socket) do
    jobs = ScheduledJobs.list_jobs()
    latest_runs = ScheduledJobs.latest_runs_by_job(Enum.map(jobs, & &1.id))
    assign(socket, jobs: jobs, latest_runs: latest_runs)
  end

  @impl true
  def handle_event("new_job", _params, socket) do
    {:noreply, assign(socket, job_editing: :new, job_form: %{}, job_form_error: nil)}
  end

  def handle_event("edit_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(id)
    {:noreply, assign(socket, job_editing: id, job_form: job_form_data(job), job_form_error: nil)}
  end

  def handle_event("cancel_job_form", _params, socket) do
    {:noreply, assign(socket, job_editing: nil, job_form: nil, job_form_error: nil)}
  end

  def handle_event("update_job_form", %{"job" => params}, socket) do
    {:noreply, assign(socket, job_form: params)}
  end

  def handle_event("save_job", %{"job" => params}, socket) do
    attrs = Map.put(params, "cron", build_cron(params))

    result =
      case socket.assigns.job_editing do
        :new -> ScheduledJobs.create_job(attrs)
        id -> ScheduledJobs.update_job(id, attrs)
      end

    case result do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(job_editing: nil, job_form: nil, job_form_error: nil)
         |> update(:form_key, &(&1 + 1))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, job_form: params, job_form_error: format_changeset_error(changeset))}
    end
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(id)
    {:ok, _job} = ScheduledJobs.update_job(job, %{"enabled" => !job.enabled})
    {:noreply, load(socket)}
  end

  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(job_editing: nil, job_form: nil, job_form_error: nil, confirm_delete: ScheduledJobs.get_job!(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete_job", _params, socket) do
    {:ok, _job} = ScheduledJobs.delete_job(socket.assigns.confirm_delete)
    {:noreply, socket |> assign(confirm_delete: nil) |> load()}
  end

  @impl true
  def handle_info(:updated, socket), do: {:noreply, load(socket)}

  # ── schedule form <-> cron ───────────────────────────────────────────────

  defp job_form_data(%Job{} = job) do
    %{
      "name" => job.name,
      "kind" => job.kind,
      "command" => job.command,
      "notify_mode" => job.notify_mode,
      "timeout_ms" => to_string(job.timeout_ms)
    }
    |> Map.merge(schedule_fields(Builder.from_cron(job.cron)))
  end

  defp schedule_fields({:every_minutes, n}),
    do: %{"schedule_type" => "every_minutes", "every_n" => to_string(n)}

  defp schedule_fields({:every_hours, n}),
    do: %{"schedule_type" => "every_hours", "every_n" => to_string(n)}

  defp schedule_fields({:daily, h, m}) do
    {lh, lm, _shift} = Builder.utc_to_local(h, m)
    %{"schedule_type" => "daily", "at" => hhmm(lh, lm)}
  end

  defp schedule_fields({:weekly, days, h, m}) do
    {lh, lm, shift} = Builder.utc_to_local(h, m)
    local_days = Enum.map(days, &Builder.shift_day(&1, shift))
    %{"schedule_type" => "weekly", "at" => hhmm(lh, lm), "days" => Enum.map(local_days, &to_string/1)}
  end

  defp schedule_fields({:custom, expr}),
    do: %{"schedule_type" => "custom", "custom_cron" => expr}

  defp hhmm(h, m), do: :io_lib.format("~2..0B:~2..0B", [h, m]) |> to_string()

  defp build_cron(params) do
    case params["schedule_type"] do
      "every_minutes" -> {:every_minutes, to_positive_int(params["every_n"], 5)}
      "every_hours" -> {:every_hours, to_positive_int(params["every_n"], 1)}
      "daily" -> daily_preset(params)
      "weekly" -> weekly_preset(params)
      _ -> {:custom, params["custom_cron"] || ""}
    end
    |> Builder.to_cron()
  end

  # The "at" time in the create/edit form is always local (the hub's
  # configured display timezone) — `Builder.local_to_utc/2` converts to
  # what `ScheduledJobs.Cron`/`TickHook` actually match against (UTC),
  # including the day-of-week shift a whole-hour zone offset can cause
  # (e.g. 11pm Pacific is already the next day in UTC).
  defp daily_preset(params) do
    {h, m} = split_time(params["at"])
    {uh, um, _shift} = Builder.local_to_utc(h, m)
    {:daily, uh, um}
  end

  defp weekly_preset(params) do
    {h, m} = split_time(params["at"])
    {uh, um, shift} = Builder.local_to_utc(h, m)
    days = (params["days"] || []) |> Enum.map(&String.to_integer/1) |> Enum.map(&Builder.shift_day(&1, shift))
    {:weekly, days, uh, um}
  end

  defp split_time(str) when is_binary(str) do
    case String.split(str, ":") do
      [h, m] ->
        with {hh, ""} <- Integer.parse(h), {mm, ""} <- Integer.parse(m) do
          {hh, mm}
        else
          _ -> {9, 0}
        end

      _ ->
        {9, 0}
    end
  end

  defp split_time(_), do: {9, 0}

  defp to_positive_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp to_positive_int(_, default), do: default

  defp describe_cron(cron_string), do: Builder.describe_local(cron_string)

  defp format_changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  defp run_badge(nil), do: {"never run", "#86948F"}
  defp run_badge(%{status: "running"}), do: {"running", "#C9A227"}
  defp run_badge(%{status: "success"}), do: {"success", "#7FB069"}
  defp run_badge(%{status: "failure"}), do: {"failure", "#C1594A"}

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="scheduled jobs" items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-8 space-y-6">
        <div class="flex items-center gap-2.5">
          <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">jobs</p>
          <span class="h-px flex-1 bg-[#242D31]"></span>
          <button
            phx-click="new_job"
            class="px-3 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            + new job
          </button>
        </div>

        <p :if={@jobs == []} class="text-[#86948F] text-sm">
          No scheduled jobs yet. Add one above.
        </p>

        <ul class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] bg-[#151B1E]">
          <.job_row
            :for={job <- @jobs}
            job={job}
            latest_run={Map.get(@latest_runs, job.id)}
          />
        </ul>
      </main>

      <.modal :if={@job_editing} title={if @job_editing == :new, do: "new job", else: "edit job"} close_event="cancel_job_form">
        <.job_form form={@job_form} error={@job_form_error} form_key={@form_key} />
        <:actions>
          <button
            :if={@job_editing != :new}
            phx-click="request_delete"
            phx-value-id={@job_editing}
            class="px-3 py-[7px] rounded-[4px] border border-[#5A2A24] text-[#E05C5C] font-mono text-[11.5px] hover:bg-[#5A2A24]/20 cursor-pointer mr-auto"
          >
            delete
          </button>
          <button
            phx-click="cancel_job_form"
            class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
          >
            cancel
          </button>
          <button
            type="submit"
            form={"job-form-#{@form_key}"}
            class="px-3 py-[7px] rounded-[4px] border border-[#3C5934] bg-[#151B1E] font-mono text-[11.5px] text-[#7FB069] hover:bg-[#1B2420] cursor-pointer"
          >
            {if @job_editing == :new, do: "create", else: "save"}
          </button>
        </:actions>
      </.modal>

      <.confirm_modal
        :if={@confirm_delete}
        title="delete job"
        message={"Delete '#{@confirm_delete.name}'? Its run history will be deleted too."}
        confirm_event="delete_job"
        confirm_label="delete"
        confirm_class="border-[#5A2A24] text-[#E05C5C] hover:bg-[#5A2A24]/20"
        cancel_event="cancel_delete"
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :confirm_event, :string, required: true
  attr :confirm_label, :string, required: true
  attr :confirm_class, :string, required: true
  attr :cancel_event, :string, required: true

  defp confirm_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4" phx-window-keydown={@cancel_event} phx-key="Escape">
      <div class="absolute inset-0 bg-black/60" phx-click={@cancel_event}></div>
      <div class="relative rounded-[6px] bg-[#151B1E] border border-[#242D31] max-w-sm w-full p-5 space-y-4">
        <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">{@title}</p>
        <p class="text-sm text-[#E6ECE9]">{@message}</p>
        <div class="flex justify-end gap-2">
          <button
            phx-click={@cancel_event}
            class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer"
          >
            cancel
          </button>
          <button
            phx-click={@confirm_event}
            class={["px-3 py-[7px] rounded-[4px] border font-mono text-[11.5px] cursor-pointer", @confirm_class]}
          >
            {@confirm_label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :close_event, :string, required: true
  slot :inner_block, required: true
  slot :actions, required: true

  defp modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60" phx-window-keydown={@close_event} phx-key="Escape">
      <div class="w-full max-w-[460px] rounded-[6px] border border-[#242D31] bg-[#151B1E] shadow-2xl" phx-click-away={@close_event}>
        <div class="px-4 py-3 border-b border-[#242D31] flex items-center justify-between">
          <p class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">{@title}</p>
          <button phx-click={@close_event} class="font-mono text-[15px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer">&times;</button>
        </div>
        <div class="p-4 max-h-[70dvh] overflow-y-auto">{render_slot(@inner_block)}</div>
        <div class="px-4 py-3 border-t border-[#242D31] flex justify-end gap-2">{render_slot(@actions)}</div>
      </div>
    </div>
    """
  end

  attr :job, :map, required: true
  attr :latest_run, :any, default: nil

  defp job_row(assigns) do
    {label, color} = run_badge(assigns.latest_run)
    assigns = assign(assigns, badge_label: label, badge_color: color)

    ~H"""
    <li class="flex items-center gap-3 px-3 py-3">
      <div class="flex-1 min-w-0">
        <.link navigate={"/scheduled-jobs/#{@job.id}"} class="text-sm hover:underline">{@job.name}</.link>
        <p class="font-mono text-[10.5px] text-[#86948F] mt-0.5">{describe_cron(@job.cron)}</p>
      </div>

      <div class="flex flex-col items-center gap-1 shrink-0">
        <span class="inline-flex items-center justify-center leading-none font-mono text-[10px] px-1.5 py-[3px] rounded-[3px] border border-[#242D31] text-[#86948F] uppercase tracking-wide">
          {@job.kind}
        </span>
        <span class="font-mono text-[10.5px]" style={"color: #{@badge_color}"}>{@badge_label}</span>
      </div>

      <label class="shrink-0">
        <input type="checkbox" checked={@job.enabled} phx-click="toggle_enabled" phx-value-id={@job.id} class="peer hidden" />
        <div class="w-8 h-[18px] rounded-full bg-[#242D31] peer-checked:bg-[#3C5934] relative cursor-pointer transition-colors">
          <div class="absolute top-[2px] left-[2px] w-[14px] h-[14px] rounded-full bg-[#86948F] peer-checked:bg-[#7FB069] peer-checked:translate-x-[14px] transition-transform"></div>
        </div>
      </label>

      <div class="flex items-center gap-2 shrink-0">
        <button
          phx-click="edit_job"
          phx-value-id={@job.id}
          aria-label="Edit job"
          class="w-7 h-7 flex items-center justify-center rounded-[4px] border border-[#242D31] font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
        >
          ✎
        </button>
      </div>
    </li>
    """
  end

  attr :form, :any, default: nil
  attr :error, :any, default: nil
  attr :form_key, :integer, required: true

  defp job_form(assigns) do
    f = assigns.form || %{}

    assigns =
      assign(assigns,
        name: f["name"] || "",
        kind: f["kind"] || "bash",
        command: f["command"] || "",
        notify_mode: f["notify_mode"] || "on_failure",
        schedule_type: f["schedule_type"] || "every_minutes",
        every_n: f["every_n"] || "5",
        at: f["at"] || "09:00",
        days: f["days"] || [],
        custom_cron: f["custom_cron"] || "",
        weekday_pairs: @weekday_labels |> Enum.sort_by(&elem(&1, 0))
      )

    ~H"""
    <form phx-submit="save_job" phx-change="update_job_form" id={"job-form-#{@form_key}"} class="space-y-3">
      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">name</label>
        <input type="text" name="job[name]" value={@name} required autocomplete="off"
          class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono" />
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">kind</label>
        <select name="job[kind]" class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono">
          <option value="bash" selected={@kind == "bash"}>bash command</option>
          <option value="prompt" selected={@kind == "prompt"}>assistant prompt</option>
        </select>
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">
          {if @kind == "prompt", do: "prompt", else: "command"}
        </label>
        <textarea name="job[command]" rows="3" required
          class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono"
        >{@command}</textarea>
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">schedule</label>
        <select name="job[schedule_type]" class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono">
          <option value="every_minutes" selected={@schedule_type == "every_minutes"}>every N minutes</option>
          <option value="every_hours" selected={@schedule_type == "every_hours"}>every N hours</option>
          <option value="daily" selected={@schedule_type == "daily"}>daily at a time</option>
          <option value="weekly" selected={@schedule_type == "weekly"}>weekly on days</option>
          <option value="custom" selected={@schedule_type == "custom"}>custom cron</option>
        </select>
      </div>

      <div :if={@schedule_type in ["every_minutes", "every_hours"]} class="flex items-center gap-2">
        <span class="font-mono text-[12px] text-[#86948F]">every</span>
        <input type="number" min="1" name="job[every_n]" value={@every_n}
          class="w-20 box-border px-2 py-[7px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono" />
        <span class="font-mono text-[12px] text-[#86948F]">{if @schedule_type == "every_hours", do: "hour(s)", else: "minute(s)"}</span>
      </div>

      <div :if={@schedule_type in ["daily", "weekly"]}>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">at</label>
        <input type="time" name="job[at]" value={@at}
          class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono" />
      </div>

      <div :if={@schedule_type == "weekly"}>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">on</label>
        <div class="flex gap-1.5">
          <label :for={{d, name} <- @weekday_pairs} class="flex-1">
            <input type="checkbox" name="job[days][]" value={to_string(d)} checked={to_string(d) in @days} class="peer hidden" />
            <div class="flex items-center justify-center px-1 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[10.5px] text-[#86948F] peer-checked:border-[#3C5934] peer-checked:text-[#7FB069] cursor-pointer">
              {name}
            </div>
          </label>
        </div>
      </div>

      <div :if={@schedule_type == "custom"}>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">cron expression</label>
        <input type="text" name="job[custom_cron]" value={@custom_cron} placeholder="*/15 * * * *" autocomplete="off"
          class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono" />
      </div>

      <div>
        <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">notify</label>
        <select name="job[notify_mode]" class="w-full box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none font-mono">
          <option value="always" selected={@notify_mode == "always"}>always</option>
          <option value="on_failure" selected={@notify_mode == "on_failure"}>on failure only</option>
          <option value="never" selected={@notify_mode == "never"}>never</option>
        </select>
      </div>

      <p :if={@error} class="font-mono text-[12px] text-[#C1594A]">{@error}</p>
    </form>
    """
  end
end
