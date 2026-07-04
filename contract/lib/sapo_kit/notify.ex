defmodule SapoKit.Notify do
  @moduledoc """
  Core notification service facade.

  Sends a message to the user via their configured notification
  destinations (managed in Settings). Modules just call:

      SapoKit.Notify.send("Task 'water plants' is due")
      SapoKit.Notify.send("Done!", image: "/path/on/server.png")

  Options:

    * `:image` — server-local path of an image to attach
    * `:destination_id` — send to a specific destination instead of the
      default one
  """

  @spec send(String.t(), keyword()) :: :ok | {:error, term()}
  def send(message, opts \\ []) when is_binary(message) do
    impl().send(message, opts)
  end

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :notify)
end
