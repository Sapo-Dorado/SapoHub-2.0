defmodule MyPlate.Migrations.AddBoards do
  use Ecto.Migration

  def change do
    create table(:my_plate_boards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    alter table(:my_plate_tasks) do
      add :board_id, :binary_id
    end

    create index(:my_plate_tasks, [:board_id, :due_date])
  end
end
