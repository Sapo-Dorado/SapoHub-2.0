defmodule SapoKit.Schema do
  @moduledoc """
  Base schema for util modules: binary_id (UUID) primary keys and
  UTC datetime timestamps, matching SapoHub conventions.

      use SapoKit.Schema

      schema "my_plate_tasks" do
        ...
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
