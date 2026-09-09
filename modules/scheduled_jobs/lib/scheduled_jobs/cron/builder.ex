defmodule ScheduledJobs.Cron.Builder do
  @moduledoc """
  Converts between the human-friendly schedule presets shown in the UI
  and the canonical cron string stored on the job. `ScheduledJobs.Cron`
  is the source of truth for matching; this module only translates for
  display/editing so the UI never has to show raw cron syntax unless the
  user explicitly picks "custom".
  """

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
end
