defmodule SapoCore.Notify do
  @moduledoc """
  Core notification service (backs `SapoKit.Notify`).

  Destination management + channel delivery, ported from v1's Notifier.
  Channels: telegram (sendMessage / sendPhoto multipart) and discord
  (webhook / webhook with file). The HTTP client is injectable via
  `config :sapo_core, :http_client` for tests.
  """

  import Ecto.Query

  require Logger

  alias SapoCore.Notify.Destination
  alias SapoCore.Repo

  # ── Destinations ───────────────────────────────────────────────────────────

  def list_destinations do
    Repo.all(from d in Destination, order_by: [desc: d.is_default, asc: d.name])
  end

  def get_destination!(id), do: Repo.get!(Destination, id)
  def get_destination(id), do: Repo.get(Destination, id)

  def get_default_destination do
    Repo.one(from d in Destination, where: d.is_default == true, limit: 1)
  end

  def create_destination(attrs) do
    %Destination{}
    |> Destination.changeset(attrs)
    |> Repo.insert()
    |> tap_ensure_single_default()
  end

  def update_destination(%Destination{} = dest, attrs) do
    dest
    |> Destination.changeset(attrs)
    |> Repo.update()
    |> tap_ensure_single_default()
  end

  def delete_destination(%Destination{} = dest), do: Repo.delete(dest)

  def set_default_destination(%Destination{} = dest) do
    Repo.transaction(fn ->
      Repo.update_all(from(d in Destination, where: d.id != ^dest.id), set: [is_default: false])
      {:ok, dest} = dest |> Destination.changeset(%{is_default: true}) |> Repo.update()
      dest
    end)
  end

  defp tap_ensure_single_default({:ok, %Destination{is_default: true} = dest} = result) do
    Repo.update_all(from(d in Destination, where: d.id != ^dest.id), set: [is_default: false])
    result
  end

  defp tap_ensure_single_default(result), do: result

  # ── Sending (SapoKit.Notify impl) ──────────────────────────────────────────

  @doc """
  Send `message` to a destination. Uses the default destination unless
  `:destination_id` is given. `:image` attaches a server-local image file.
  """
  @spec send(String.t(), keyword()) :: :ok | {:error, term()}
  def send(message, opts \\ []) do
    destination =
      case Keyword.get(opts, :destination_id) do
        nil -> get_default_destination()
        id -> get_destination(id)
      end

    case destination do
      nil -> {:error, :no_destination}
      dest -> deliver(message, dest, opts)
    end
  end

  defp deliver(message, %Destination{channel: "telegram", config: config}, opts) do
    token = Map.get(config, "bot_token")
    chat_id = Map.get(config, "chat_id")

    case opts[:image] do
      nil ->
        post_json(
          "https://api.telegram.org/bot#{token}/sendMessage",
          %{chat_id: chat_id, text: message, parse_mode: "Markdown"},
          "telegram"
        )

      image_path ->
        with {:ok, content, filename, mime} <- read_image(image_path) do
          post_multipart(
            "https://api.telegram.org/bot#{token}/sendPhoto",
            [
              chat_id: chat_id,
              caption: message,
              parse_mode: "Markdown",
              photo: {content, filename: filename, content_type: mime}
            ],
            "telegram"
          )
        end
    end
  end

  defp deliver(message, %Destination{channel: "discord", config: config}, opts) do
    webhook_url = Map.get(config, "webhook_url")

    case opts[:image] do
      nil ->
        post_json(webhook_url, %{content: message}, "discord")

      image_path ->
        with {:ok, content, filename, mime} <- read_image(image_path) do
          post_multipart(
            webhook_url,
            [
              payload_json: Jason.encode!(%{content: message}),
              "files[0]": {content, filename: filename, content_type: mime}
            ],
            "discord"
          )
        end
    end
  end

  defp deliver(_message, %Destination{channel: other}, _opts) do
    {:error, {:unknown_channel, other}}
  end

  # ── HTTP helpers ───────────────────────────────────────────────────────────

  defp post_json(url, payload, channel) do
    handle_response(http_client().request(:post, url, json: payload), channel)
  end

  defp post_multipart(url, parts, channel) do
    handle_response(http_client().request(:post, url, form_multipart: parts), channel)
  end

  defp handle_response({:ok, %{status: status}}, _channel) when status in 200..299, do: :ok

  defp handle_response({:ok, %{status: status, body: body}}, channel) do
    Logger.error("#{channel} API error: #{status} - #{inspect(body)}")
    {:error, {:api_error, status}}
  end

  defp handle_response({:error, reason}, channel) do
    Logger.error("#{channel} request failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp read_image(path) do
    case File.read(path) do
      {:ok, content} ->
        filename = Path.basename(path)
        {:ok, content, filename, mime_type(filename)}

      {:error, reason} ->
        Logger.error("failed to read image #{path}: #{inspect(reason)}")
        {:error, {:file_read_error, reason}}
    end
  end

  defp mime_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  defp http_client, do: Application.get_env(:sapo_core, :http_client, SapoCore.HTTP)
end
