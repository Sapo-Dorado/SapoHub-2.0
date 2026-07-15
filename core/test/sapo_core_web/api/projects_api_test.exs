defmodule SapoCoreWeb.Api.ProjectsApiTest do
  use SapoCoreWeb.ConnCase, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "sapo_projects_api_test_#{System.unique_integer([:positive])}")
    previous = Application.get_env(:sapo_core, :storage_root)
    Application.put_env(:sapo_core, :storage_root, root)

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

  defp bare_remote! do
    path = Path.join(System.tmp_dir!(), "sapo_projects_api_remote_#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["init", "--bare", "-b", "main", path])
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  test "projects CRUD via API, backed by a real (local) git clone", %{conn: conn} do
    remote = bare_remote!()

    conn1 = post(conn, ~p"/api/projects", %{"name" => "api-proj", "github_url" => remote})
    assert %{"id" => id, "name" => "api-proj"} = json_response(conn1, 201)

    assert [%{"id" => ^id}] = json_response(get(conn, ~p"/api/projects"), 200)
    assert %{"id" => ^id, "github_url" => ^remote} = json_response(get(conn, ~p"/api/projects/#{id}"), 200)

    conn2 = delete(conn, ~p"/api/projects/#{id}")
    assert response(conn2, 204)
  end

  test "create validation errors are 422", %{conn: conn} do
    conn = post(conn, ~p"/api/projects", %{"name" => "Not Valid"})
    assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
  end

  test "show/delete 404 for unknown project", %{conn: conn} do
    id = Ecto.UUID.generate()
    assert json_response(get(conn, ~p"/api/projects/#{id}"), 404)
    assert json_response(delete(conn, ~p"/api/projects/#{id}"), 404)
  end

  test "delete is blocked (409) when there are uncommitted changes", %{conn: conn} do
    remote = bare_remote!()
    conn1 = post(conn, ~p"/api/projects", %{"name" => "dirty-api", "github_url" => remote})
    %{"id" => id} = json_response(conn1, 201)

    File.write!(Path.join(Projects.Disk.source_path("dirty-api"), "scratch.txt"), "wip")

    conn2 = delete(conn, ~p"/api/projects/#{id}")
    assert %{"error" => reason} = json_response(conn2, 409)
    assert reason =~ "uncommitted"
  end

  test "push pushes a local commit even with unrelated uncommitted changes present", %{conn: conn} do
    remote = bare_remote!()
    conn1 = post(conn, ~p"/api/projects", %{"name" => "push-api", "github_url" => remote})
    %{"id" => id} = json_response(conn1, 201)
    source = Projects.Disk.source_path("push-api")

    File.write!(Path.join(source, "committed.txt"), "landed\n")
    {_, 0} = System.cmd("git", ["add", "committed.txt"], cd: source)
    {_, 0} = System.cmd("git", ["commit", "-m", "add committed file"], cd: source)
    File.write!(Path.join(source, "wip.txt"), "not committed")

    conn2 = post(conn, ~p"/api/projects/#{id}/sync")
    assert %{"error" => reason} = json_response(conn2, 422)
    assert reason =~ "uncommitted"

    conn3 = post(conn, ~p"/api/projects/#{id}/push")
    assert %{"output" => _} = json_response(conn3, 200)

    verify_clone = Path.join(System.tmp_dir!(), "sapo_projects_api_verify_#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["clone", remote, verify_clone])
    assert File.exists?(Path.join(verify_clone, "committed.txt"))
    File.rm_rf!(verify_clone)
  end

  test "params API", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{"name" => "param-proj", "github_url" => "x"})

    conn1 = put(conn, ~p"/api/projects/#{project.id}/params/TOKEN", %{"value" => "abc"})
    assert %{"key" => "TOKEN", "value" => "abc"} = json_response(conn1, 200)

    assert [%{"key" => "TOKEN", "value" => "abc"}] = json_response(get(conn, ~p"/api/projects/#{project.id}/params"), 200)

    conn2 = delete(conn, ~p"/api/projects/#{project.id}/params/TOKEN")
    assert response(conn2, 204)
    assert json_response(get(conn, ~p"/api/projects/#{project.id}/params"), 200) == []
  end

  test "scripts API: lists non-sudo scripts and rejects sudo run with 403", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{"name" => "script-proj", "github_url" => "x"})
    scripts_dir = Path.join(Projects.Disk.source_path("script-proj"), "scripts")
    File.mkdir_p!(scripts_dir)

    File.write!(Path.join(scripts_dir, "safe.sh"), """
    #!/usr/bin/env bash
    # SAPO_SCRIPT_NAME: Safe
    echo ok
    """)

    File.write!(Path.join(scripts_dir, "danger.sh"), """
    #!/usr/bin/env bash
    # SAPO_SCRIPT_NAME: Danger
    # SAPO_SCRIPT_SUDO: true
    echo nope
    """)

    resp = json_response(get(conn, ~p"/api/projects/#{project.id}/scripts"), 200)
    assert Enum.map(resp, & &1["name"]) == ["Safe"]

    conn1 =
      post(conn, ~p"/api/projects/#{project.id}/scripts/run", %{
        "script_file" => Path.join(scripts_dir, "danger.sh")
      })

    assert %{"error" => _} = json_response(conn1, 403)
  end

  test "scripts API: runs a safe script and returns captured output", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{"name" => "run-proj", "github_url" => "x"})
    scripts_dir = Path.join(Projects.Disk.source_path("run-proj"), "scripts")
    File.mkdir_p!(scripts_dir)
    script_path = Path.join(scripts_dir, "greet.sh")

    File.write!(script_path, """
    #!/usr/bin/env bash
    # SAPO_SCRIPT_NAME: Greet
    # SAPO_SCRIPT_PARAM: WHO
    echo "hi $WHO"
    """)

    conn1 =
      post(conn, ~p"/api/projects/#{project.id}/scripts/run", %{
        "script_file" => script_path,
        "params" => %{"WHO" => "api"}
      })

    assert %{"exit_code" => 0, "output" => output} = json_response(conn1, 200)
    assert output =~ "hi api"
  end

  test "scripts API rejects path traversal", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{"name" => "traversal-proj", "github_url" => "x"})

    conn1 = post(conn, ~p"/api/projects/#{project.id}/scripts/run", %{"script_file" => "../../etc/passwd"})
    assert json_response(conn1, 400)
  end
end
