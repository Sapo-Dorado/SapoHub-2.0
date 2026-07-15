defmodule ProjectsTest do
  use SapoCore.DataCase, async: false

  alias Projects.{Disk, Git, ScriptCommand, ScriptParser}

  setup do
    root = Path.join(System.tmp_dir!(), "sapo_projects_test_#{System.unique_integer([:positive])}")
    previous = Application.get_env(:sapo_core, :storage_root)
    Application.put_env(:sapo_core, :storage_root, root)

    # Git needs an identity to commit; set it via env so it's inherited by
    # `System.cmd("git", ...)` without touching any shared/global config.
    prev_env =
      for key <- ~w(GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL) do
        {key, System.get_env(key)}
      end

    System.put_env("GIT_AUTHOR_NAME", "Test")
    System.put_env("GIT_AUTHOR_EMAIL", "test@example.com")
    System.put_env("GIT_COMMITTER_NAME", "Test")
    System.put_env("GIT_COMMITTER_EMAIL", "test@example.com")

    on_exit(fn ->
      Application.put_env(:sapo_core, :storage_root, previous)
      File.rm_rf!(root)
      Enum.each(prev_env, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end)

    %{root: root}
  end

  # Creates a local bare "remote" repo to clone/push/pull against, so tests
  # never touch the network or need GitHub credentials.
  defp bare_remote! do
    path = Path.join(System.tmp_dir!(), "sapo_projects_remote_#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["init", "--bare", "-b", "main", path])
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  # ── Project CRUD ────────────────────────────────────────────────────────

  test "create/update/delete project" do
    {:ok, project} = Projects.create_project(%{"name" => "demo", "github_url" => "https://example.com/x.git"})
    assert project.name == "demo"
    assert project.position == 0

    {:ok, updated} = Projects.update_project(project, %{github_url: "https://example.com/y.git"})
    assert updated.github_url == "https://example.com/y.git"

    {:ok, _} = Projects.delete_project(updated)
    assert_raise Ecto.NoResultsError, fn -> Projects.get_project!(updated.id) end
  end

  test "create_project rejects invalid names" do
    assert {:error, changeset} = Projects.create_project(%{"name" => "Not Valid!", "github_url" => "x"})
    assert %{name: _} = errors_on(changeset)
  end

  test "list_projects orders by position then name" do
    {:ok, a} = Projects.create_project(%{"name" => "bbb", "github_url" => "x"})
    {:ok, b} = Projects.create_project(%{"name" => "aaa", "github_url" => "x"})

    # Both default to position 0, so falls back to name order: "aaa" < "bbb".
    assert Enum.map(Projects.list_projects(), & &1.id) == [b.id, a.id]

    Projects.reorder_projects([a.id, b.id])
    assert Enum.map(Projects.list_projects(), & &1.id) == [a.id, b.id]
  end

  # ── Params ──────────────────────────────────────────────────────────────

  test "params CRUD, keyed per project" do
    {:ok, project} = Projects.create_project(%{"name" => "p1", "github_url" => "x"})

    {:ok, _} = Projects.upsert_param(project.id, "TOKEN", "abc")
    assert [%{key: "TOKEN", value: "abc"}] = Projects.list_params(project.id)

    {:ok, _} = Projects.upsert_param(project.id, "TOKEN", "xyz")
    assert [%{key: "TOKEN", value: "xyz"}] = Projects.list_params(project.id)

    Projects.delete_param(project.id, "TOKEN")
    assert Projects.list_params(project.id) == []
  end

  # ── Disk + Git + full setup/pull/delete lifecycle ──────────────────────

  test "create_and_setup clones an empty repo, bootstraps it, and marks pulled" do
    remote = bare_remote!()

    {:ok, project} = Projects.create_and_setup(%{"name" => "cloned", "github_url" => remote})

    assert project.last_pulled_at
    assert File.dir?(Path.join(Disk.project_root("cloned"), "source/.git"))
    assert File.exists?(Disk.claude_md_path("cloned"))
    assert File.exists?(Path.join(Disk.source_path("cloned"), "README.md"))
  end

  test "create_and_setup rolls back the DB row when clone fails" do
    {:error, _reason} = Projects.create_and_setup(%{"name" => "badclone", "github_url" => "/no/such/remote"})

    assert Projects.list_projects() == []
  end

  test "pull_project fetches and merges remote changes" do
    remote = bare_remote!()
    {:ok, project} = Projects.create_and_setup(%{"name" => "pullme", "github_url" => remote})

    # Simulate someone else pushing to the remote.
    other_clone = Path.join(System.tmp_dir!(), "sapo_projects_other_#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["clone", remote, other_clone])
    File.write!(Path.join(other_clone, "note.txt"), "hi from elsewhere\n")
    {_, 0} = System.cmd("git", ["add", "note.txt"], cd: other_clone)
    {_, 0} = System.cmd("git", ["commit", "-m", "add note"], cd: other_clone)
    {_, 0} = System.cmd("git", ["push"], cd: other_clone)
    File.rm_rf!(other_clone)

    {:ok, updated} = Projects.pull_project(project)
    assert updated.last_pulled_at

    assert File.exists?(Disk.source_path(project.name) <> "/note.txt")
  end

  test "push_project lands local commits even with unrelated uncommitted changes present" do
    remote = bare_remote!()
    {:ok, project} = Projects.create_and_setup(%{"name" => "pushme", "github_url" => remote})
    source = Disk.source_path(project.name)

    File.write!(Path.join(source, "committed.txt"), "landed\n")
    {_, 0} = System.cmd("git", ["add", "committed.txt"], cd: source)
    {_, 0} = System.cmd("git", ["commit", "-m", "add committed file"], cd: source)

    # Work-in-progress left in the tree — pull_project (a fetch+merge, which
    # needs a clean tree to be safe) refuses to run at all with this present.
    File.write!(Path.join(source, "wip.txt"), "not committed")
    assert {:error, reason} = Projects.pull_project(project)
    assert reason =~ "uncommitted"

    # push_project doesn't care — it never touches the working tree.
    assert {:ok, _output} = Projects.push_project(project)

    verify_clone = Path.join(System.tmp_dir!(), "sapo_projects_verify_#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["clone", remote, verify_clone])
    assert File.exists?(Path.join(verify_clone, "committed.txt"))
    File.rm_rf!(verify_clone)
  end

  test "delete_project_safely blocks on uncommitted changes, then succeeds once clean" do
    remote = bare_remote!()
    {:ok, project} = Projects.create_and_setup(%{"name" => "dirty", "github_url" => remote})

    File.write!(Path.join(Disk.source_path(project.name), "scratch.txt"), "wip")

    assert {:error, reason} = Projects.delete_project_safely(project)
    assert reason =~ "uncommitted"

    File.rm!(Path.join(Disk.source_path(project.name), "scratch.txt"))
    assert :ok = Projects.delete_project_safely(project)
    refute File.exists?(Disk.project_root(project.name))
  end

  test "Git.safe_to_delete? is safe when source was never cloned" do
    assert {:ok, :safe} = Git.safe_to_delete?("nonexistent-project")
  end

  # ── Scripts: discovery, params, sudo gating ─────────────────────────────

  defp write_script!(dir, filename, header_lines, body \\ "echo hi\n") do
    File.mkdir_p!(dir)

    content =
      "#!/usr/bin/env bash\n" <>
        Enum.map_join(header_lines, "", &"# #{&1}\n") <>
        body

    path = Path.join(dir, filename)
    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end

  test "ScriptParser discovers scripts, params, sudo and sync flags" do
    scripts_dir = Path.join(Disk.source_path("scripty"), "scripts")

    write_script!(scripts_dir, "deploy.sh", [
      "SAPO_SCRIPT_NAME: Deploy",
      "SAPO_SCRIPT_PARAM: TARGET",
      "SAPO_SCRIPT_PARAM_OPTIONAL: DRY_RUN",
      "SAPO_SCRIPT_SUDO: true",
      "SAPO_SCRIPT_SYNC: true"
    ])

    write_script!(scripts_dir, "hello.sh", ["SAPO_SCRIPT_NAME: Hello"])
    write_script!(scripts_dir, "no_header.sh", ["some other comment"])

    scripts = ScriptParser.parse_scripts("scripty")
    assert Enum.map(scripts, & &1.name) == ["Deploy", "Hello"]

    deploy = Enum.find(scripts, &(&1.name == "Deploy"))
    assert deploy.params == ["TARGET"]
    assert deploy.optional_params == ["DRY_RUN"]
    assert deploy.sudo
    assert deploy.sync

    hello = Enum.find(scripts, &(&1.name == "Hello"))
    refute hello.sudo
    refute hello.sync
    assert hello.params == []
  end

  test "ScriptCommand.build rejects sudo scripts and builds env for others", %{root: root} do
    assert {:error, :sudo_unsupported} = ScriptCommand.build(%{sudo: true, file: "x.sh"}, root)

    script = %{sudo: false, file: "/tmp/x.sh", params_values: %{"A" => "1", "B" => "two"}}
    assert {:ok, {bash, ["/tmp/x.sh"], env, cwd}} = ScriptCommand.build(script, root)

    assert bash =~ "bash"
    assert cwd == Path.join(root, "source")
    assert {"A", "1"} in env
    assert {"B", "two"} in env
  end

  test "run_script_blocking rejects sudo scripts before ever building a command" do
    {:ok, project} = Projects.create_project(%{"name" => "runtest", "github_url" => "x"})

    assert {:error, :sudo_unsupported} =
             Projects.run_script_blocking(project, %{sudo: true, file: "whatever.sh"}, %{})
  end

  test "run_script_blocking runs a real script and captures output" do
    scripts_dir = Path.join(Disk.source_path("runner"), "scripts")
    script_path = write_script!(scripts_dir, "greet.sh", ["SAPO_SCRIPT_NAME: Greet", "SAPO_SCRIPT_PARAM: WHO"], "echo \"hi $WHO\"\n")

    {:ok, project} = Projects.create_project(%{"name" => "runner", "github_url" => "x"})
    script = %{name: "Greet", file: script_path, params: ["WHO"], optional_params: [], sudo: false, sync: false}

    assert {:ok, %{output: output, exit_code: 0}} =
             Projects.run_script_blocking(project, script, %{"WHO" => "world"})

    assert output =~ "hi world"
  end
end
