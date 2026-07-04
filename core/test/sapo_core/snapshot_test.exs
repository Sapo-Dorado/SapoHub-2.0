defmodule SapoCore.SnapshotTest do
  # No DataCase: VACUUM INTO cannot run inside the sandbox transaction, so
  # snapshot tests use unboxed connections and clean up after themselves.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SapoCore.Repo
  alias SapoCore.Snapshot
  alias SapoCore.Storage

  setup do
    marker = "snap-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Ecto.Adapters.SQL.query!(Repo, "DELETE FROM hello_greetings WHERE name LIKE 'snap-%'")
      end)

      File.rm_rf!(Application.fetch_env!(:sapo_core, :snapshots_dir))
    end)

    %{marker: marker}
  end

  test "full round trip: seed -> save -> restore into scratch -> assert", %{marker: marker} do
    # Seed a DB row and a storage file.
    Sandbox.unboxed_run(Repo, fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO hello_greetings (id, name, inserted_at, updated_at) " <>
          "VALUES (?1, ?2, datetime('now'), datetime('now'))",
        [Ecto.UUID.bingenerate(), marker]
      )
    end)

    Storage.ensure_dirs!()
    storage_file = Storage.path(:sapo_hello, "keep.txt")
    File.write!(storage_file, "keep me: #{marker}")
    on_exit(fn -> File.rm(storage_file) end)

    # Save (outside the sandbox: VACUUM INTO needs a plain connection).
    {:ok, archive} =
      Sandbox.unboxed_run(Repo, fn -> Snapshot.save() end)

    assert String.ends_with?(archive, ".tar.gz")
    assert [%{name: name} | _] = Snapshot.list()
    assert name == Path.basename(archive)

    # Restore into scratch locations (the boot path does the same against
    # the live paths before the app starts).
    scratch = Path.join(System.tmp_dir!(), "sapo_restore_#{System.unique_integer([:positive])}")
    scratch_db = Path.join(scratch, "db/restored.sqlite3")
    scratch_storage = Path.join(scratch, "storage")
    on_exit(fn -> File.rm_rf!(scratch) end)

    assert :ok = Snapshot.restore_from(archive, scratch_db, scratch_storage)

    # DB content survived — inspect the restored file directly.
    {:ok, conn} = Exqlite.Sqlite3.open(scratch_db)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM hello_greetings WHERE name = ?1")

    :ok = Exqlite.Sqlite3.bind(stmt, [marker])
    {:row, [1]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok = Exqlite.Sqlite3.close(conn)

    # Storage content survived.
    assert File.read!(Path.join(scratch_storage, "sapo_hello/keep.txt")) ==
             "keep me: #{marker}"
  end

  test "manifest describes modules and migrations", %{marker: _} do
    {:ok, archive} = Sandbox.unboxed_run(Repo, fn -> Snapshot.save() end)

    tmp = Path.join(System.tmp_dir!(), "sapo_manifest_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {_out, 0} = System.cmd("tar", ["xzf", archive, "-C", tmp])
    manifest = tmp |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

    assert manifest["manifest_version"] == 1
    assert Enum.any?(manifest["modules"], &(&1["id"] == "sapo_hello"))
    assert manifest["migration_versions"] != []
  end

  test "restore rejects archives without a valid manifest" do
    bogus = Path.join(System.tmp_dir!(), "bogus-#{System.unique_integer([:positive])}.tar.gz")
    content = Path.join(System.tmp_dir!(), "bogus-content-#{System.unique_integer([:positive])}")
    File.mkdir_p!(content)
    File.write!(Path.join(content, "junk.txt"), "junk")
    {_out, 0} = System.cmd("tar", ["czf", bogus, "-C", content, "."])
    on_exit(fn -> File.rm_rf!(content) && File.rm!(bogus) end)

    scratch = Path.join(System.tmp_dir!(), "sapo_reject_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(scratch) end)

    assert {:error, :manifest_missing} =
             Snapshot.restore_from(bogus, Path.join(scratch, "db.sqlite3"), scratch)

    refute File.exists?(Path.join(scratch, "db.sqlite3"))
  end

  test "maybe_restore is a no-op without a staged archive" do
    refute File.exists?(Application.fetch_env!(:sapo_core, :restore_pending))
    assert :ok = SapoCore.Release.maybe_restore()
  end

  test "concurrent writes succeed under WAL/busy_timeout (smoke)", %{marker: marker} do
    results =
      1..15
      |> Enum.map(fn i ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Ecto.Adapters.SQL.query!(
              Repo,
              "INSERT INTO hello_greetings (id, name, inserted_at, updated_at) " <>
                "VALUES (?1, ?2, datetime('now'), datetime('now'))",
              [Ecto.UUID.bingenerate(), "#{marker}-#{i}"]
            )

            :ok
          end)
        end)
      end)
      |> Task.await_many(15_000)

    assert Enum.all?(results, &(&1 == :ok))

    count =
      Sandbox.unboxed_run(Repo, fn ->
        %{rows: [[n]]} =
          Ecto.Adapters.SQL.query!(
            Repo,
            "SELECT COUNT(*) FROM hello_greetings WHERE name LIKE ?1",
            ["#{marker}-%"]
          )

        n
      end)

    assert count == 15
  end
end
