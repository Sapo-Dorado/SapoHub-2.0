defmodule SapoCoreWeb.Api.CoreServicesApiTest do
  use SapoCoreWeb.ConnCase, async: false

  alias SapoCore.FakeHTTP
  alias SapoCore.Notify

  setup do
    FakeHTTP.install(self())
    :ok
  end

  describe "POST /api/notify" do
    test "sends via the default destination", %{conn: conn} do
      {:ok, _} =
        Notify.create_destination(%{
          "name" => "Phone",
          "channel" => "telegram",
          "config" => %{"bot_token" => "tok", "chat_id" => "42"},
          "is_default" => true
        })

      conn = post(conn, ~p"/api/notify", %{"message" => "hi"})

      assert json_response(conn, 200) == %{"status" => "sent"}
      assert_receive {:http, :post, _url, _opts}
    end

    test "422 when no destination configured", %{conn: conn} do
      conn = post(conn, ~p"/api/notify", %{"message" => "hi"})
      assert json_response(conn, 422)["error"] =~ "no default"
    end

    test "400 without a message", %{conn: conn} do
      conn = post(conn, ~p"/api/notify", %{})
      assert json_response(conn, 400)
    end
  end

  describe "notification destinations" do
    test "CRUD + set-default round trip", %{conn: conn} do
      conn1 =
        post(conn, ~p"/api/notification-destinations", %{
          "name" => "Phone",
          "channel" => "telegram",
          "config" => %{"bot_token" => "tok", "chat_id" => "42"}
        })

      assert %{"id" => id, "is_default" => false} = json_response(conn1, 201)

      conn2 = post(conn, ~p"/api/notification-destinations/#{id}/set-default")
      assert json_response(conn2, 200)["is_default"] == true

      conn3 = get(conn, ~p"/api/notification-destinations")
      assert [%{"id" => ^id}] = json_response(conn3, 200)

      conn4 = delete(conn, ~p"/api/notification-destinations/#{id}")
      assert response(conn4, 204)

      conn5 = get(conn, ~p"/api/notification-destinations")
      assert json_response(conn5, 200) == []
    end

    test "invalid destination is a 422 with errors", %{conn: conn} do
      conn =
        post(conn, ~p"/api/notification-destinations", %{
          "name" => "Bad",
          "channel" => "telegram",
          "config" => %{}
        })

      assert %{"errors" => %{"config" => _}} = json_response(conn, 422)
    end
  end

  describe "storage files API" do
    test "lists, downloads and deletes files in the hello module dir", %{conn: conn} do
      dir = SapoCore.Storage.dir(:sapo_hello)
      File.mkdir_p!(dir)
      file = Path.join(dir, "api_test.txt")
      File.write!(file, "hello storage")
      on_exit(fn -> File.rm(file) end)

      conn1 = get(conn, ~p"/api/storage/files")
      assert Enum.any?(json_response(conn1, 200), &(&1["path"] == "sapo_hello/api_test.txt"))

      conn2 = get(conn, ~p"/api/storage/files/sapo_hello/api_test.txt")
      assert response(conn2, 200) == "hello storage"

      conn3 = delete(conn, ~p"/api/storage/files/sapo_hello/api_test.txt")
      assert response(conn3, 204)
      refute File.exists?(file)
    end

    test "404s on traversal attempts", %{conn: conn} do
      conn = get(conn, ~p"/api/storage/files/sapo_hello/../../etc/passwd")
      assert json_response(conn, 404)
    end
  end
end
