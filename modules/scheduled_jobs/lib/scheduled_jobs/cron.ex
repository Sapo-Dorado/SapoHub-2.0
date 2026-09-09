defmodule ScheduledJobs.Cron do
  @moduledoc """
  Hand-rolled 5-field cron parser/matcher (minute hour day-of-month month
  day-of-week). No external dependency is available to modules (the
  contract restricts a module to depending only on `sapo_module_kit`), so
  this implements the common subset of cron syntax directly:

    * `*`               — any value
    * `5`                — a single value
    * `1,2,5`            — a list
    * `1-5`              — a range
    * `*/5`, `1-20/5`    — a step, optionally over a sub-range

  Day-of-week accepts both `0` and `7` for Sunday (both common in the
  wild); `7` is normalized to `0` at parse time.
  """

  defstruct [:minute, :hour, :dom, :month, :dow, :expr]

  @type field_set :: MapSet.t(non_neg_integer())
  @type t :: %__MODULE__{
          minute: field_set,
          hour: field_set,
          dom: field_set,
          month: field_set,
          dow: field_set,
          expr: String.t()
        }

  @minute_range 0..59
  @hour_range 0..23
  @dom_range 1..31
  @month_range 1..12
  @dow_parse_range 0..7

  @doc "Parses a 5-field cron expression."
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(expr) when is_binary(expr) do
    case String.split(String.trim(expr)) do
      [mi, h, d, mo, w] ->
        with {:ok, minute} <- parse_field(mi, @minute_range),
             {:ok, hour} <- parse_field(h, @hour_range),
             {:ok, dom} <- parse_field(d, @dom_range),
             {:ok, month} <- parse_field(mo, @month_range),
             {:ok, raw_dow} <- parse_field(w, @dow_parse_range) do
          dow = MapSet.new(raw_dow, fn 7 -> 0; n -> n end)

          {:ok,
           %__MODULE__{
             minute: minute,
             hour: hour,
             dom: dom,
             month: month,
             dow: dow,
             expr: String.trim(expr)
           }}
        end

      _ ->
        {:error,
         "cron expression must have exactly 5 fields: minute hour day-of-month month day-of-week"}
    end
  end

  def parse(_), do: {:error, "cron expression must be a string"}

  @doc "True if a valid `parse/1` result, without needing the struct."
  @spec valid?(String.t()) :: boolean()
  def valid?(expr), do: match?({:ok, _}, parse(expr))

  @doc """
  Whether `dt` (already truncated to the minute — seconds/microseconds
  are ignored) is due under `cron`.
  """
  @spec matches?(t(), DateTime.t()) :: boolean()
  def matches?(%__MODULE__{} = cron, %DateTime{} = dt) do
    MapSet.member?(cron.minute, dt.minute) and
      MapSet.member?(cron.hour, dt.hour) and
      MapSet.member?(cron.month, dt.month) and
      dom_dow_match?(cron, dt)
  end

  # Standard (if surprising) cron quirk: when BOTH day-of-month and
  # day-of-week are restricted (neither is "*"), a date matching EITHER
  # is enough — they're OR'd, not AND'd. When only one is restricted it
  # behaves as a normal AND (the wildcard side is trivially true).
  defp dom_dow_match?(%__MODULE__{} = cron, %DateTime{} = dt) do
    dom_wild? = wild?(cron.dom, @dom_range)
    dow_wild? = wild?(cron.dow, 0..6)

    dom_ok = MapSet.member?(cron.dom, dt.day)
    dow_ok = MapSet.member?(cron.dow, rem(Date.day_of_week(DateTime.to_date(dt)), 7))

    cond do
      dom_wild? and dow_wild? -> true
      dom_wild? -> dow_ok
      dow_wild? -> dom_ok
      true -> dom_ok or dow_ok
    end
  end

  defp wild?(field_set, range), do: MapSet.size(field_set) == Range.size(range)

  @doc """
  Best-effort human summary of a cron expression, for the UI to fall back
  on when a job's schedule doesn't match one of the builder presets.
  Falls back to the raw expression when no readable pattern is found.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = cron) do
    dom_wild? = wild?(cron.dom, @dom_range)
    month_wild? = wild?(cron.month, @month_range)
    dow_wild? = wild?(cron.dow, 0..6)

    cond do
      not month_wild? ->
        cron.expr

      wild?(cron.minute, @minute_range) and wild?(cron.hour, @hour_range) and dom_wild? and
          dow_wild? ->
        "every minute"

      not is_nil(step_n(cron.minute, @minute_range)) and wild?(cron.hour, @hour_range) and
          dom_wild? and dow_wild? ->
        "every #{step_n(cron.minute, @minute_range)} minutes"

      single?(cron.minute) and MapSet.member?(cron.minute, 0) and
          not is_nil(step_n(cron.hour, @hour_range)) and dom_wild? and dow_wild? ->
        "every #{step_n(cron.hour, @hour_range)} hours"

      single?(cron.minute) and single?(cron.hour) and dom_wild? and dow_wild? ->
        "daily at #{hhmm(cron)}"

      single?(cron.minute) and single?(cron.hour) and dom_wild? and not dow_wild? ->
        "weekly on #{weekday_names(cron.dow)} at #{hhmm(cron)}"

      true ->
        cron.expr
    end
  end

  defp single?(field_set), do: MapSet.size(field_set) == 1

  # Returns the step `n` if `field_set` is exactly "every n units" over
  # `range` (n > 1), else nil.
  defp step_n(field_set, range) do
    values = Enum.to_list(range)

    Enum.find(2..Range.size(range)//1, fn n ->
      MapSet.new(Enum.take_every(values, n)) == field_set
    end)
  end

  defp hhmm(%__MODULE__{minute: minute, hour: hour}) do
    [h] = MapSet.to_list(hour)
    [m] = MapSet.to_list(minute)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> to_string()
  end

  @weekday_names %{0 => "Sun", 1 => "Mon", 2 => "Tue", 3 => "Wed", 4 => "Thu", 5 => "Fri", 6 => "Sat"}

  defp weekday_names(dow) do
    dow |> Enum.sort() |> Enum.map(&Map.fetch!(@weekday_names, &1)) |> Enum.join(",")
  end

  # ── field parsing ──────────────────────────────────────────────────────

  defp parse_field(str, range) do
    str
    |> String.split(",")
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_component(part, range) do
        {:ok, values} -> {:cont, {:ok, [values | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, lists} -> {:ok, lists |> List.flatten() |> MapSet.new()}
      {:error, _} = err -> err
    end
  end

  defp parse_component("*", range), do: {:ok, Enum.to_list(range)}

  defp parse_component("*/" <> step, range) do
    with {:ok, n} <- parse_positive_int(step) do
      {:ok, Enum.take_every(Enum.to_list(range), n)}
    end
  end

  defp parse_component(part, range) do
    case String.split(part, "/") do
      [range_part, step_part] ->
        with {:ok, base} <- parse_range_or_int(range_part, range),
             {:ok, n} <- parse_positive_int(step_part) do
          {:ok, base |> Enum.sort() |> Enum.take_every(n)}
        end

      [single] ->
        parse_range_or_int(single, range)
    end
  end

  defp parse_range_or_int(str, range) do
    case String.split(str, "-") do
      [a_str, b_str] ->
        with {:ok, a} <- parse_int(a_str),
             {:ok, b} <- parse_int(b_str) do
          if a <= b and a in range and b in range do
            {:ok, Enum.to_list(a..b)}
          else
            {:error, "invalid range: #{str}"}
          end
        end

      [single] ->
        with {:ok, n} <- parse_int(single) do
          if n in range, do: {:ok, [n]}, else: {:error, "value out of range: #{single}"}
        end
    end
  end

  defp parse_positive_int(str) do
    with {:ok, n} <- parse_int(str) do
      if n > 0, do: {:ok, n}, else: {:error, "step must be positive: #{str}"}
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "not an integer: #{str}"}
    end
  end
end
