defmodule SapoCore.NotifyTest do
  use SapoCore.DataCase, async: false

  alias SapoCore.FakeHTTP
  alias SapoCore.Notify

  @telegram_attrs %{
    "name" => "Phone",
    "channel" => "telegram",
    "config" => %{"bot_token" => "tok", "chat_id" => "42"},
    "is_default" => true
  }

  @discord_attrs %{
    "name" => "Server",
    "channel" => "discord",
    "config" => %{"webhook_url" => "https://discord.example/hook"}
  }

  setup do
    FakeHTTP.install(self())
    :ok
  end

  describe "destinations" do
    test "create validates channel-specific config" do
      assert {:error, changeset} =
               Notify.create_destination(%{
                 "name" => "Bad",
                 "channel" => "telegram",
                 "config" => %{"bot_token" => "tok"}
               })

      assert %{config: [error]} = errors_on(changeset)
      assert error =~ "chat_id"

      assert {:error, changeset} =
               Notify.create_destination(%{
                 "name" => "Bad",
                 "channel" => "carrier_pigeon",
                 "config" => %{}
               })

      assert %{channel: _} = errors_on(changeset)
    end

    test "only one default at a time" do
      {:ok, first} = Notify.create_destination(@telegram_attrs)
      {:ok, second} = Notify.create_destination(Map.put(@discord_attrs, "is_default", true))

      assert Notify.get_default_destination().id == second.id
      refute Repo.reload!(first).is_default

      {:ok, _} = Notify.set_default_destination(Repo.reload!(first))
      assert Notify.get_default_destination().id == first.id
      refute Repo.reload!(second).is_default
    end
  end

  describe "send/2" do
    test "errors when no default destination exists" do
      assert {:error, :no_destination} = Notify.send("hi")
    end

    test "sends telegram message to the default destination" do
      {:ok, _} = Notify.create_destination(@telegram_attrs)

      assert :ok = Notify.send("hello *world*")

      assert_receive {:http, :post, "https://api.telegram.org/bottok/sendMessage", opts}
      assert opts[:json] == %{chat_id: "42", text: "hello *world*", parse_mode: "Markdown"}
    end

    test "sends to a specific destination by id" do
      {:ok, _default} = Notify.create_destination(@telegram_attrs)
      {:ok, discord} = Notify.create_destination(@discord_attrs)

      assert :ok = Notify.send("ping", destination_id: discord.id)

      assert_receive {:http, :post, "https://discord.example/hook", opts}
      assert opts[:json] == %{content: "ping"}
    end

    test "attaches an image via multipart" do
      {:ok, _} = Notify.create_destination(@telegram_attrs)
      path = Path.join(System.tmp_dir!(), "notify_test.png")
      File.write!(path, <<137, 80, 78, 71>>)
      on_exit(fn -> File.rm(path) end)

      assert :ok = Notify.send("with pic", image: path)

      assert_receive {:http, :post, "https://api.telegram.org/bottok/sendPhoto", opts}
      parts = opts[:form_multipart]
      assert parts[:caption] == "with pic"
      assert {<<137, 80, 78, 71>>, file_opts} = parts[:photo]
      assert file_opts[:filename] == "notify_test.png"
      assert file_opts[:content_type] == "image/png"
    end

    test "missing image file is an error, nothing sent" do
      {:ok, _} = Notify.create_destination(@telegram_attrs)

      assert {:error, {:file_read_error, :enoent}} =
               Notify.send("oops", image: "/nonexistent.png")

      refute_receive {:http, _, _, _}
    end

    test "non-2xx responses surface as api errors" do
      {:ok, _} = Notify.create_destination(@telegram_attrs)
      FakeHTTP.respond_with({:ok, %{status: 400, body: %{"description" => "bad"}, headers: []}})

      assert {:error, {:api_error, 400}} = Notify.send("hi")
    end
  end
end
