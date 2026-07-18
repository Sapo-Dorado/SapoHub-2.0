defmodule Recipes.Migrations.CreateRecipesTables do
  use Ecto.Migration

  def change do
    create table(:recipes_ingredients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recipes_ingredients, ["lower(name)"],
             unique: true,
             name: :recipes_ingredients_name_ci_index
           )

    create table(:recipes_recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :directions, :text, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create index(:recipes_recipes, ["lower(name)"], name: :recipes_recipes_name_ci_index)

    create table(:recipes_recipe_ingredients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipe_id, references(:recipes_recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :ingredient_id, references(:recipes_ingredients, type: :binary_id), null: false
      add :amount, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:recipes_recipe_ingredients, [:recipe_id, :position])
    create index(:recipes_recipe_ingredients, [:ingredient_id])

    create table(:recipes_shopping_list_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ingredient_id, references(:recipes_ingredients, type: :binary_id), null: false
      add :note, :string
      add :checked, :boolean, null: false, default: false
      add :checked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # At most one OPEN item per ingredient — the invariant the whole
    # find-or-create / merge-safe-uncheck design in Recipes leans on.
    # SQLite stores :boolean as 0/1, hence the literal `checked = 0`.
    create index(:recipes_shopping_list_items, [:ingredient_id],
             unique: true,
             where: "checked = 0",
             name: :recipes_shopping_list_items_open_ingredient_index
           )

    create table(:recipes_shopping_list_contributions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :shopping_list_item_id,
          references(:recipes_shopping_list_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :recipe_id, references(:recipes_recipes, type: :binary_id, on_delete: :nilify_all)
      add :recipe_name, :string, null: false
      add :amount, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:recipes_shopping_list_contributions, [:shopping_list_item_id])
    create index(:recipes_shopping_list_contributions, [:recipe_id])
  end
end
