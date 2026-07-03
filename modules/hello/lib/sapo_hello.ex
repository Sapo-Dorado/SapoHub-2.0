defmodule SapoHello do
  @moduledoc """
  Context for the hello reference module: minimal CRUD over greetings,
  demonstrating database access through `SapoKit.Repo`.
  """

  import Ecto.Query

  alias SapoHello.Greeting
  alias SapoKit.Repo

  def list_greetings do
    Repo.all(from g in Greeting, order_by: [desc: g.inserted_at])
  end

  def count_greetings do
    Repo.aggregate(Greeting, :count)
  end

  def get_greeting!(id), do: Repo.get!(Greeting, id)

  def create_greeting(attrs) do
    result =
      %Greeting{}
      |> Greeting.changeset(attrs)
      |> Repo.insert()

    with {:ok, greeting} <- result do
      SapoKit.PubSub.broadcast("hello:greetings", {:greeting_created, greeting})
      {:ok, greeting}
    end
  end

  def delete_greeting(%Greeting{} = greeting) do
    Repo.delete(greeting)
  end
end
