defmodule SapoKit.PubSub do
  @moduledoc """
  Facade over the host application's Phoenix.PubSub.

  Core points it at the real pubsub:

      config :sapo_module_kit, pubsub: SapoCore.PubSub
  """

  defp pubsub, do: Application.fetch_env!(:sapo_module_kit, :pubsub)

  def subscribe(topic), do: Phoenix.PubSub.subscribe(pubsub(), topic)
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(pubsub(), topic)
  def broadcast(topic, message), do: Phoenix.PubSub.broadcast(pubsub(), topic, message)
  def broadcast!(topic, message), do: Phoenix.PubSub.broadcast!(pubsub(), topic, message)
end
