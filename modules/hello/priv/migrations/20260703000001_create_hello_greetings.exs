defmodule SapoHello.Migrations.CreateHelloGreetings do
  use Ecto.Migration

  def change do
    create table(:hello_greetings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
