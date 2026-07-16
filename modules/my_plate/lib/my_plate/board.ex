defmodule MyPlate.Board do
  @moduledoc false
  use SapoKit.Schema

  import Ecto.Changeset

  schema "my_plate_boards" do
    field :name, :string
    field :position, :integer

    timestamps()
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name, :position])
    |> validate_required([:name])
  end
end
