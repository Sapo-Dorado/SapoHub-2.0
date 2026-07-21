defmodule SapoKit.Time do
  @moduledoc """
  Display-timezone facade. The DB always stores/queries UTC — this is only
  for the last step, rendering a `DateTime` for a human, using the
  instance-wide `services.sapohub.timezone` setting (default "Etc/UTC").

  Modules use this instead of calling `Calendar.strftime/2` directly on a
  raw UTC `DateTime` whenever the result is shown to a person (as opposed
  to, say, a log line or a filename, where UTC is the right call).
  """

  @spec local(DateTime.t()) :: DateTime.t()
  def local(%DateTime{} = dt), do: impl().local(dt)

  @doc "Configured IANA display timezone (e.g. \"America/Los_Angeles\"), for building a zoned DateTime directly rather than shifting an existing one."
  @spec zone_name() :: String.t()
  def zone_name, do: impl().display_timezone()

  @spec format(DateTime.t(), String.t()) :: String.t()
  def format(%DateTime{} = dt, fmt), do: impl().format(dt, fmt)

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :time)
end
