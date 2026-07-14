defmodule SapoCore.ReleaseTest do
  use ExUnit.Case, async: true

  test "migration_paths includes core and enabled module migration dirs" do
    paths = SapoCore.Release.migration_paths()

    assert Enum.any?(paths, &String.ends_with?(&1, "sapo_hello")),
           "expected hello module migrations in #{inspect(paths)}"
  end

  test "migration_paths namespaces versions by module id so identical timestamps don't collide" do
    paths = SapoCore.Release.migration_paths()

    versions =
      for path <- paths,
          file <- File.ls!(path),
          String.ends_with?(file, ".exs") do
        [version | _] = String.split(file, "_", parts: 2)
        version
      end

    assert length(versions) == length(Enum.uniq(versions))
  end
end
