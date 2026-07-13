defmodule SapoCore.Time do
  @moduledoc """
  Display-timezone helper. The DB always stores and queries in UTC —
  nothing in this module writes or persists anything. This is ONLY for the
  last step, rendering a `DateTime` for a human, using the IANA zone name
  configured via `services.sapohub.timezone` (nix option, default
  "Etc/UTC", read into `:sapo_core, :display_timezone` at boot).

  A bad/unknown zone name is a config mistake, not a reason to crash a
  render: `local/1` falls back to UTC and logs a warning the first time it
  hits a bad name (Logger itself naturally rate-limits repeats via its own
  dedup, but see `warn_once/1` below — no need to spam every render).
  """

  require Logger

  @doc "Configured IANA display timezone (e.g. \"America/Los_Angeles\"). Defaults to \"Etc/UTC\"."
  @spec display_timezone() :: String.t()
  def display_timezone do
    Application.get_env(:sapo_core, :display_timezone, "Etc/UTC")
  end

  @doc """
  Shift a UTC `DateTime` into the configured display timezone. Falls back to
  the original (UTC) datetime, unchanged, if the configured zone name is
  invalid or the time zone database can't resolve it.
  """
  @spec local(DateTime.t()) :: DateTime.t()
  def local(%DateTime{} = dt) do
    tz = display_timezone()

    case DateTime.shift_zone(dt, tz) do
      {:ok, shifted} ->
        shifted

      {:error, reason} ->
        warn_once(tz, reason)
        dt
    end
  end

  @doc "Format a UTC `DateTime` in the configured display timezone, `strftime`-style."
  @spec format(DateTime.t(), String.t()) :: String.t()
  def format(%DateTime{} = dt, fmt) do
    dt |> local() |> Calendar.strftime(fmt)
  end

  # Logs once per (bad zone name) rather than on every single render — a
  # misconfigured timezone will otherwise log on every page view / clock
  # tick, drowning out everything else in the journal.
  defp warn_once(tz, reason) do
    key = {__MODULE__, :warned, tz}

    if :persistent_term.get(key, false) == false do
      Logger.warning(
        "SapoCore.Time: display timezone #{inspect(tz)} could not be resolved (#{inspect(reason)}); falling back to UTC for display"
      )

      :persistent_term.put(key, true)
    end
  end
end
