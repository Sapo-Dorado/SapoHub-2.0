defmodule SapoCore.ReleaseTest do
  use ExUnit.Case, async: true

  test "migration_paths includes core and enabled module migration dirs" do
    paths = SapoCore.Release.migration_paths()

    assert Enum.any?(paths, &String.ends_with?(&1, "sapo_hello/priv/migrations")),
           "expected hello module migrations in #{inspect(paths)}"
  end
end
