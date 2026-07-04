defmodule SapoCore.Notify.Destination do
  @moduledoc """
  A notification destination (`core_notification_destinations`).

  `config` is channel-specific: telegram needs `bot_token` + `chat_id`,
  discord needs `webhook_url`. Exactly one destination can be the default.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @channels ~w(telegram discord)

  schema "core_notification_destinations" do
    field :name, :string
    field :channel, :string
    field :config, :map, default: %{}
    field :is_default, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def channels, do: @channels

  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:name, :channel, :config, :is_default])
    |> validate_required([:name, :channel, :config])
    |> validate_inclusion(:channel, @channels)
    |> validate_config()
  end

  defp validate_config(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_config(changeset) do
    config = get_field(changeset, :config) || %{}

    required =
      case get_field(changeset, :channel) do
        "telegram" -> ["bot_token", "chat_id"]
        "discord" -> ["webhook_url"]
        _ -> []
      end

    Enum.reduce(required, changeset, fn key, acc ->
      case Map.get(config, key) do
        value when is_binary(value) and value != "" -> acc
        _ -> add_error(acc, :config, "missing required key #{key}")
      end
    end)
  end
end
