defmodule ScheduledJobs.Cron.Builder do
  @moduledoc """
  Converts between the human-friendly schedule presets shown in the UI
  and the canonical cron string stored on the job. `ScheduledJobs.Cron`
  is the source of truth for matching; this module only translates for
  display/editing so the UI never has to show raw cron syntax unless the
  user explicitly picks "custom".

  Also owns the local-timezone boundary for "daily"/"weekly" presets:
  `ScheduledJobs.Cron` matches in UTC (correct — that's what the tick
  hook actually compares against) and stays timezone-agnostic on
  purpose, but a person authoring "daily at 10:00" means their own
  local time (`SapoKit.Time`, same facade every module uses), not UTC.
  """

  alias ScheduledJobs.Cron

  @weekday_short %{0 => "Sun", 1 => "Mon", 2 => "Tue", 3 => "Wed", 4 => "Thu", 5 => "Fri", 6 => "Sat"}

  @doc """
  Builds a canonical cron string from a preset.

    * `{:every_minutes, n}`
    * `{:every_hours, n}`
    * `{:daily, hour, minute}`
    * `{:weekly, [0..6], hour, minute}`
    * `{:custom, cron_string}`
  """
  @spec to_cron(tuple()) :: String.t()
  def to_cron({:every_minutes, n}) when is_integer(n) and n > 0, do: "*/#{n} * * * *"
  def to_cron({:every_hours, n}) when is_integer(n) and n > 0, do: "0 */#{n} * * *"

  def to_cron({:daily, hour, minute}) when hour in 0..23 and minute in 0..59,
    do: "#{minute} #{hour} * * *"

  def to_cron({:weekly, days, hour, minute}) when hour in 0..23 and minute in 0..59 do
    days_str = days |> Enum.sort() |> Enum.join(",")
    "#{minute} #{hour} * * #{days_str}"
  end

  def to_cron({:custom, cron_string}) when is_binary(cron_string), do: cron_string

  @doc """
  Best-effort match of a cron string back to one of the presets above
  (for pre-filling the edit form); falls back to `{:custom, expr}` when
  the expression doesn't correspond to a simple preset.
  """
  @spec from_cron(String.t()) :: tuple()
  def from_cron(expr) when is_binary(expr) do
    case String.split(String.trim(expr)) do
      [mi, h, "*", "*", "*"] -> from_minute_hour(mi, h, expr)
      [mi, h, "*", "*", dow] -> from_weekly(mi, h, dow, expr)
      _ -> {:custom, expr}
    end
  end

  defp from_minute_hour("*/" <> n, "*", _expr) do
    case Integer.parse(n) do
      {n, ""} -> {:every_minutes, n}
      _ -> {:custom, "*/#{n} * * * *"}
    end
  end

  defp from_minute_hour("0", "*/" <> n, _expr) do
    case Integer.parse(n) do
      {n, ""} -> {:every_hours, n}
      _ -> {:custom, "0 */#{n} * * *"}
    end
  end

  defp from_minute_hour(mi, h, expr) do
    with {m, ""} <- Integer.parse(mi), {hr, ""} <- Integer.parse(h) do
      {:daily, hr, m}
    else
      _ -> {:custom, expr}
    end
  end

  defp from_weekly(mi, h, dow, expr) do
    with {m, ""} <- Integer.parse(mi),
         {hr, ""} <- Integer.parse(h),
         days when is_list(days) <- parse_days(dow) do
      {:weekly, days, hr, m}
    else
      _ -> {:custom, expr}
    end
  end

  defp parse_days(dow) do
    dow
    |> String.split(",")
    |> Enum.reduce_while([], fn part, acc ->
      case Integer.parse(part) do
        {n, ""} when n in 0..7 -> {:cont, [rem(n, 7) | acc]}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      days -> Enum.reverse(days)
    end
  end

  @doc """
  Human-readable schedule description in the hub's LOCAL display
  timezone — the counterpart to `ScheduledJobs.Cron.describe/1`, which
  only knows UTC. Falls back to `Cron.describe/1` for any shape other
  than daily/weekly (every-N-minutes/hours don't shift across a
  whole-hour zone offset, so those are already correct as-is).
  """
  @spec describe_local(String.t()) :: String.t()
  def describe_local(cron_string) do
    case Cron.parse(cron_string) do
      {:ok, cron} ->
        case Cron.daily_or_weekly(cron) do
          {:daily, h, m} ->
            {lh, lm, _shift} = utc_to_local(h, m)
            "daily at #{hhmm(lh, lm)}"

          {:weekly, days, h, m} ->
            {lh, lm, shift} = utc_to_local(h, m)
            "weekly on #{weekday_names(Enum.map(days, &shift_day(&1, shift)))} at #{hhmm(lh, lm)}"

          nil ->
            Cron.describe(cron)
        end

      {:error, _} ->
        cron_string
    end
  end

  @doc "Converts a local HH:MM to UTC, returning `{hour, minute, day_shift}` — `day_shift` is -1/0/1 depending on whether the zone offset pushed the moment into the previous/same/next calendar day."
  @spec local_to_utc(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), integer()}
  def local_to_utc(h, m) do
    zone = SapoKit.Time.zone_name()
    ref_date = Date.utc_today()
    {:ok, local_dt} = DateTime.new(ref_date, Time.new!(h, m, 0), zone)
    utc_dt = DateTime.shift_zone!(local_dt, "Etc/UTC")
    {utc_dt.hour, utc_dt.minute, Date.diff(DateTime.to_date(utc_dt), ref_date)}
  end

  @doc "Converts a UTC HH:MM to local, returning `{hour, minute, day_shift}` (see `local_to_utc/2`)."
  @spec utc_to_local(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), integer()}
  def utc_to_local(h, m) do
    zone = SapoKit.Time.zone_name()
    ref_date = Date.utc_today()
    {:ok, utc_dt} = DateTime.new(ref_date, Time.new!(h, m, 0), "Etc/UTC")
    local_dt = DateTime.shift_zone!(utc_dt, zone)
    {local_dt.hour, local_dt.minute, Date.diff(DateTime.to_date(local_dt), ref_date)}
  end

  @doc "Applies a `local_to_utc/2`/`utc_to_local/2` day_shift to a cron day-of-week (0=Sun..6=Sat)."
  @spec shift_day(non_neg_integer(), integer()) :: non_neg_integer()
  def shift_day(dow, shift), do: rem(dow + shift + 7, 7)

  defp hhmm(h, m), do: :io_lib.format("~2..0B:~2..0B", [h, m]) |> to_string()

  defp weekday_names(days) do
    days |> Enum.sort() |> Enum.map(&Map.fetch!(@weekday_short, &1)) |> Enum.join(",")
  end
end
