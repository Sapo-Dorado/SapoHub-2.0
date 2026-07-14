defmodule RemindersWeb.Live.Index do
  @moduledoc """
  Reminders page: create-reminder form, pending list (inline edit/cancel),
  and a recent-activity strip for sent/failed deliveries (dismiss = cancel).

  v1 put reminder creation in a modal launched from the dashboard, plus an
  alert bar on the dashboard itself for sent/failed reminders. v2's
  dashboard is launcher-only (no embedded widgets — see
  workspace/design/style-guide.md), so all of that now lives on this one
  dedicated page instead, reusing `my_plate`'s established card/list/
  inline-edit patterns rather than the dashboard-modal shape.
  """
  use SapoKit.Web, :live_view

  alias Reminders.Reminder

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("reminders:updates")

    {:ok,
     socket
     |> assign(editing_id: nil, form_key: 0)
     |> load()}
  end

  @impl true
  def handle_event("create_reminder", %{"message" => message} = params, socket)
      when message != "" do
    date = Map.get(params, "date", "")
    time = Map.get(params, "time", "")

    attrs = %{
      message: message,
      remind_at: parse_remind_at(date, time),
      time_specific: time != ""
    }

    case Reminders.create_reminder(attrs) do
      {:ok, _reminder} ->
        # Bump form_key so the (uncontrolled) form remounts fresh instead of
        # LiveView's default morphdom preserving the just-typed input value.
        {:noreply, socket |> load() |> update(:form_key, &(&1 + 1))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not set reminder")}
    end
  end

  def handle_event("create_reminder", _params, socket), do: {:noreply, socket}

  def handle_event("edit_reminder", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  def handle_event("cancel_edit_reminder", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("update_reminder", %{"reminder_id" => id, "message" => message} = params, socket) do
    date = Map.get(params, "date", "")
    time = Map.get(params, "time", "")

    attrs = %{
      message: message,
      remind_at: parse_remind_at(date, time),
      time_specific: time != ""
    }

    case Reminders.update_reminder(id, attrs) do
      {:ok, _} -> {:noreply, socket |> assign(editing_id: nil) |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update reminder")}
    end
  end

  def handle_event("cancel_reminder", %{"id" => id}, socket) do
    Reminders.cancel_reminder(id)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info(:reminder_updated, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load(socket) do
    assign(socket,
      page_title: "reminders",
      pending: Reminders.list_pending(),
      sent: Reminders.list_sent(),
      failed: Reminders.list_failed()
    )
  end

  # ── Time parsing/formatting (ported from v1 DashboardLive) ────────────────

  defp today, do: DateTime.now!(timezone()) |> DateTime.to_date()
  defp timezone, do: SapoKit.ModuleConfig.get(:reminders, :timezone) || "Etc/UTC"

  defp default_remind_time do
    SapoKit.ModuleConfig.get(:reminders, :default_remind_time) || "09:00"
  end

  defp parse_remind_at("", time_str), do: parse_remind_at(Date.to_iso8601(today()), time_str)

  defp parse_remind_at(date_str, "") do
    tz = timezone()
    date = Date.from_iso8601!(date_str)

    time =
      if date == today() do
        DateTime.now!(tz) |> DateTime.add(3600) |> DateTime.to_time()
      else
        Time.from_iso8601!(default_remind_time() <> ":00")
      end

    DateTime.new!(date, time, tz) |> DateTime.shift_zone!("Etc/UTC")
  end

  defp parse_remind_at(date_str, time_str) do
    tz = timezone()
    date = Date.from_iso8601!(date_str)
    time = Time.from_iso8601!(time_str <> ":00")
    DateTime.new!(date, time, tz) |> DateTime.shift_zone!("Etc/UTC")
  end

  defp format_reminder_time(%Reminder{} = reminder) do
    tz = timezone()
    local_dt = DateTime.shift_zone!(reminder.remind_at, tz)
    date = DateTime.to_date(local_dt)
    diff = Date.diff(date, today())

    date_str =
      cond do
        diff == 0 -> "today"
        diff == 1 -> "tomorrow"
        diff > 0 and diff <= 7 -> Calendar.strftime(date, "%A") |> String.downcase()
        true -> Calendar.strftime(date, "%b %-d")
      end

    if reminder.time_specific do
      time_str = Calendar.strftime(local_dt, "%-I:%M %p") |> String.downcase()
      "#{date_str} at #{time_str}"
    else
      date_str
    end
  end

  defp form_date_value(%Reminder{} = reminder) do
    reminder.remind_at |> DateTime.shift_zone!(timezone()) |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp form_time_value(%Reminder{time_specific: false}), do: ""

  defp form_time_value(%Reminder{} = reminder) do
    reminder.remind_at |> DateTime.shift_zone!(timezone()) |> Calendar.strftime("%H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline
        crumb="reminders"
        items={@statusline}
        right={"#{length(@pending)} pending"}
      />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-6 space-y-7">
        <h1 class="font-mono text-[13.5px] font-semibold text-[#E6ECE9]">reminders</h1>

        <section :if={@sent != [] or @failed != []} class="space-y-2">
          <div
            :for={reminder <- @sent}
            class="flex items-start gap-3 px-4 py-3 rounded-[4px] bg-[#151B1E] border border-[#242D31] border-l-[3px] border-l-[#7FB069]"
          >
            <div class="flex-1 min-w-0 text-sm text-[#7FB069]">{reminder.message}</div>
            <button
              phx-click="cancel_reminder"
              phx-value-id={reminder.id}
              class="font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer flex-shrink-0"
            >
              dismiss
            </button>
          </div>
          <div
            :for={reminder <- @failed}
            class="flex items-start gap-3 px-4 py-3 rounded-[4px] bg-[#151B1E] border border-[#242D31] border-l-[3px] border-l-[#C1594A]"
          >
            <div class="flex-1 min-w-0">
              <div class="text-sm text-[#C1594A]">Reminder failed: {reminder.message}</div>
              <div :if={reminder.failure_reason} class="font-mono text-[11px] text-[#C1594A]/70 mt-0.5">
                {reminder.failure_reason}
              </div>
            </div>
            <button
              phx-click="cancel_reminder"
              phx-value-id={reminder.id}
              class="font-mono text-[11px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer flex-shrink-0"
            >
              dismiss
            </button>
          </div>
        </section>

        <section class="rounded-[4px] bg-[#151B1E] border border-[#242D31] p-4">
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-3">
            set a reminder
          </div>
          <form phx-submit="create_reminder" class="space-y-3" id={"create-reminder-form-#{@form_key}"}>
            <div>
              <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">message</label>
              <input
                type="text"
                name="message"
                placeholder="Remind me to..."
                required
                class="w-full px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none"
              />
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="min-w-0">
                <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">date</label>
                <input
                  type="date"
                  name="date"
                  value={Date.to_iso8601(today())}
                  required
                  class="w-full min-w-0 box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none [color-scheme:dark]"
                />
              </div>
              <div class="min-w-0">
                <label class="block font-mono text-[11px] text-[#86948F] mb-1.5">time (optional)</label>
                <input
                  type="time"
                  name="time"
                  class="w-full min-w-0 box-border px-3 py-[9px] rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none [color-scheme:dark]"
                />
              </div>
            </div>
            <div class="flex justify-end pt-1">
              <button
                type="submit"
                class="px-4 py-[7px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[12px] font-semibold tracking-[.02em] cursor-pointer"
              >
                set reminder
              </button>
            </div>
          </form>
        </section>

        <section>
          <div class="font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F] mb-3">
            upcoming
          </div>

          <p :if={@pending == []} class="text-[#86948F] text-sm">
            No reminders set. Add one above.
          </p>

          <ul :if={@pending != []} class="rounded-[4px] border border-[#242D31] bg-[#151B1E] divide-y divide-[#242D31]">
            <li :for={reminder <- @pending} class="px-3 py-2.5">
              <%= if @editing_id == reminder.id do %>
                <form phx-submit="update_reminder" class="space-y-2.5">
                  <input type="hidden" name="reminder_id" value={reminder.id} />
                  <input
                    type="text"
                    name="message"
                    value={reminder.message}
                    required
                    class="w-full px-3 py-2 rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none"
                  />
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                    <input
                      type="date"
                      name="date"
                      value={form_date_value(reminder)}
                      required
                      class="w-full min-w-0 box-border px-3 py-2 rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none [color-scheme:dark]"
                    />
                    <input
                      type="time"
                      name="time"
                      value={form_time_value(reminder)}
                      class="w-full min-w-0 box-border px-3 py-2 rounded-[4px] bg-[#0D1113] border border-[#242D31] text-sm text-[#E6ECE9] focus:border-[#7FB069] focus:outline-none [color-scheme:dark]"
                    />
                  </div>
                  <div class="flex gap-2 justify-end">
                    <button
                      type="button"
                      phx-click="cancel_edit_reminder"
                      class="px-3 py-[6px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
                    >
                      cancel
                    </button>
                    <button
                      type="submit"
                      class="px-3 py-[6px] rounded-[4px] bg-[#7FB069] hover:bg-[#8fbf7b] text-[#0C1409] font-mono text-[11.5px] font-semibold cursor-pointer"
                    >
                      save
                    </button>
                  </div>
                </form>
              <% else %>
                <div class="flex items-center gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="text-sm text-[#E6ECE9] truncate">{reminder.message}</div>
                    <div class="font-mono text-[11px] text-[#86948F] mt-0.5">{format_reminder_time(reminder)}</div>
                  </div>
                  <button
                    phx-click="edit_reminder"
                    phx-value-id={reminder.id}
                    aria-label="Edit reminder"
                    class="font-mono text-[12px] text-[#86948F] hover:text-[#E6ECE9] cursor-pointer flex-shrink-0"
                  >
                    edit
                  </button>
                  <button
                    phx-click="cancel_reminder"
                    phx-value-id={reminder.id}
                    data-confirm="Cancel this reminder?"
                    aria-label="Cancel reminder"
                    class="font-mono text-[14px] text-[#86948F] hover:text-[#C1594A] cursor-pointer flex-shrink-0"
                  >
                    ×
                  </button>
                </div>
              <% end %>
            </li>
          </ul>
        </section>
      </main>
    </div>
    """
  end
end
