defmodule SapoCore.StorageTest do
  use ExUnit.Case, async: false

  alias SapoCore.Storage

  defmodule FilesModule do
    use SapoKit.Module
    def id, do: :files_mod
    def title, do: "Files"
    def storage_paths, do: ["exports", "cache/thumbs"]
  end

  defmodule NoStorageModule do
    use SapoKit.Module
    def id, do: :no_storage_mod
    def title, do: "NoStorage"
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

  test "storage is opt-in: modules without storage_paths get nothing", %{root: root} do
    :ok = Storage.ensure_dirs!([NoStorageModule, FilesModule])

    refute File.dir?(Path.join(root, "no_storage_mod"))

    # Even if a file existed there, the API would not expose it.
    File.mkdir_p!(Path.join(root, "no_storage_mod"))
    File.write!(Path.join(root, "no_storage_mod/sneaky.txt"), "hi")

    assert Storage.list_files([NoStorageModule, FilesModule]) == []

    assert {:error, :invalid_path} =
             Storage.resolve("no_storage_mod/sneaky.txt", [NoStorageModule, FilesModule])
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

  test "delete_file removes a plain file", %{root: root} do
    :ok = Storage.ensure_dirs!([FilesModule])
    file = Path.join(root, "files_mod/doomed.txt")
    File.write!(file, "bye")

    assert :ok = Storage.delete_file("files_mod/doomed.txt", [FilesModule])
    refute File.exists?(file)
  end

  test "delete_file recursively removes a folder", %{root: root} do
    :ok = Storage.ensure_dirs!([FilesModule])
    nested = Path.join(root, "files_mod/exports/nested")
    File.mkdir_p!(nested)
    File.write!(Path.join(nested, "a.txt"), "hi")

    assert :ok = Storage.delete_file("files_mod/exports", [FilesModule])
    refute File.exists?(Path.join(root, "files_mod/exports"))
  end

  test "delete_file returns error for nonexistent path" do
    :ok = Storage.ensure_dirs!([FilesModule])
    assert {:error, :not_found} = Storage.delete_file("files_mod/nope.txt", [FilesModule])
  end

  describe "list_dir/2" do
    test "top level lists one entry per opted-in module with counts", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule, NoStorageModule])
      File.write!(Path.join(root, "files_mod/top.txt"), "hi")

      assert {:ok, %{dirs: dirs, files: []}} = Storage.list_dir(nil, [FilesModule, NoStorageModule])
      assert [%{name: "files_mod", path: "files_mod", count: count}] = dirs
      assert count >= 1
    end

    test "nested path lists subfolders and files relative to the api path", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule])
      File.write!(Path.join(root, "files_mod/exports/a.csv"), "a,b\n")

      assert {:ok, %{dirs: [], files: [file]}} = Storage.list_dir("files_mod/exports", [FilesModule])
      assert file.name == "a.csv"
      assert file.path == "files_mod/exports/a.csv"
    end

    test "listing the module root itself works (abs == base)", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule])
      File.write!(Path.join(root, "files_mod/top.txt"), "hi")

      assert {:ok, %{dirs: dirs, files: files}} = Storage.list_dir("files_mod", [FilesModule])
      assert Enum.any?(dirs, &(&1.name == "exports"))
      assert Enum.any?(files, &(&1.name == "top.txt"))
    end

    test "rejects traversal and unknown modules" do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:error, :invalid_path} = Storage.list_dir("files_mod/../..", [FilesModule])
      assert {:error, :invalid_path} = Storage.list_dir("other_mod", [FilesModule])
    end
  end

  describe "mkdir/2" do
    test "creates a nested folder under a module's storage dir", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule])

      assert :ok = Storage.mkdir("files_mod/exports/newfolder", [FilesModule])
      assert File.dir?(Path.join(root, "files_mod/exports/newfolder"))
    end

    test "rejects traversal outside the module dir" do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:error, :invalid_path} = Storage.mkdir("files_mod/../escape", [FilesModule])
    end

    test "rejects unknown modules" do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:error, :invalid_path} = Storage.mkdir("other_mod/newfolder", [FilesModule])
    end
  end

  describe "resolve_dir/2" do
    test "resolves a module's root dir itself (abs == base)", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:ok, abs} = Storage.resolve_dir("files_mod", [FilesModule])
      assert abs == Path.expand(Path.join(root, "files_mod"))
    end

    test "resolves a nested folder path", %{root: root} do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:ok, abs} = Storage.resolve_dir("files_mod/exports", [FilesModule])
      assert abs == Path.expand(Path.join(root, "files_mod/exports"))
    end

    test "rejects traversal and unknown modules" do
      :ok = Storage.ensure_dirs!([FilesModule])
      assert {:error, :invalid_path} = Storage.resolve_dir("files_mod/../..", [FilesModule])
      assert {:error, :invalid_path} = Storage.resolve_dir("other_mod", [FilesModule])
    end
  end
end
