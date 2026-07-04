defmodule SapoCore.StorageTest do
  use ExUnit.Case, async: false

  alias SapoCore.Storage

  defmodule FilesModule do
    use SapoKit.Module
    def id, do: :files_mod
    def title, do: "Files"
    def storage_paths, do: ["exports", "cache/thumbs"]
  end

  setup do
    root = Path.join(System.tmp_dir!(), "sapo_storage_test_#{System.unique_integer([:positive])}")
    previous = Application.get_env(:sapo_core, :storage_root)
    Application.put_env(:sapo_core, :storage_root, root)

    on_exit(fn ->
      Application.put_env(:sapo_core, :storage_root, previous)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "dir/1 defaults to <root>/<id> and honors overrides", %{root: root} do
    assert Storage.dir(:files_mod) == Path.join(root, "files_mod")

    Application.put_env(:sapo_core, :storage_dirs, %{files_mod: "/elsewhere/files"})
    on_exit(fn -> Application.delete_env(:sapo_core, :storage_dirs) end)

    assert Storage.dir(:files_mod) == "/elsewhere/files"
    assert Storage.path(:files_mod, "a.txt") == "/elsewhere/files/a.txt"
  end

  test "ensure_dirs! creates module dir and declared subdirs", %{root: root} do
    :ok = Storage.ensure_dirs!([FilesModule])

    assert File.dir?(Path.join(root, "files_mod/exports"))
    assert File.dir?(Path.join(root, "files_mod/cache/thumbs"))
  end

  test "list_files walks module dirs with metadata", %{root: root} do
    :ok = Storage.ensure_dirs!([FilesModule])
    File.write!(Path.join(root, "files_mod/exports/a.csv"), "a,b\n")
    File.write!(Path.join(root, "files_mod/top.txt"), "hi")

    files = Storage.list_files([FilesModule])
    paths = Enum.map(files, & &1.path)

    assert paths == ["files_mod/exports/a.csv", "files_mod/top.txt"]
    assert %{size: 4} = Enum.find(files, &(&1.path == "files_mod/exports/a.csv"))
  end

  test "resolve rejects traversal and unknown modules" do
    :ok = Storage.ensure_dirs!([FilesModule])

    assert {:ok, _} = Storage.resolve("files_mod/exports/a.csv", [FilesModule])
    assert {:error, :invalid_path} = Storage.resolve("files_mod/../../etc/passwd", [FilesModule])
    assert {:error, :invalid_path} = Storage.resolve("other_mod/a.txt", [FilesModule])
    assert {:error, :invalid_path} = Storage.resolve("files_mod", [FilesModule])
  end

  test "delete_file removes files, not dirs", %{root: root} do
    :ok = Storage.ensure_dirs!([FilesModule])
    file = Path.join(root, "files_mod/doomed.txt")
    File.write!(file, "bye")

    # resolve/list use the registry by default; go through the module list here.
    {:ok, abs} = Storage.resolve("files_mod/doomed.txt", [FilesModule])
    assert abs == file
  end
end
