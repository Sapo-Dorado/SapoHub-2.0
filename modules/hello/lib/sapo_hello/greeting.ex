defmodule SapoHello.Greeting do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  schema "hello_greetings" do
    field :name, :string

    timestamps()
  end

  def changeset(greeting, attrs) do
    greeting
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
  end
end
