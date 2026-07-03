defmodule SapoHelloWeb.Api.GreetingsController do
  @moduledoc false
  use SapoKit.Web, :controller

  def index(conn, _params) do
    json(conn, Enum.map(SapoHello.list_greetings(), &serialize/1))
  end

  def create(conn, params) do
    case SapoHello.create_greeting(params) do
      {:ok, greeting} ->
        conn
        |> put_status(:created)
        |> json(serialize(greeting))

      {:error, changeset} ->
        render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    greeting = SapoHello.get_greeting!(id)
    {:ok, _} = SapoHello.delete_greeting(greeting)
    send_resp(conn, :no_content, "")
  end

  defp serialize(greeting) do
    %{
      id: greeting.id,
      name: greeting.name,
      inserted_at: greeting.inserted_at
    }
  end
end
