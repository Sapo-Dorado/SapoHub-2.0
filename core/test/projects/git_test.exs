defmodule Projects.GitTest do
  # GITHUB_TOKEN is read from the process environment (shared with core's
  # sapohub-deploy secret) — async: false since these mutate it globally.
  use ExUnit.Case, async: false

  alias Projects.Git

  setup do
    original = System.get_env("GITHUB_TOKEN")

    on_exit(fn ->
      if original, do: System.put_env("GITHUB_TOKEN", original), else: System.delete_env("GITHUB_TOKEN")
    end)

    :ok
  end

  describe "authed_url/1" do
    test "rewrites an https:// URL with x-access-token when GITHUB_TOKEN is set" do
      System.put_env("GITHUB_TOKEN", "ghp_fake_token")

      assert Git.authed_url("https://github.com/example/repo.git") ==
               "https://x-access-token:ghp_fake_token@github.com/example/repo.git"
    end

    test "leaves the URL unchanged when GITHUB_TOKEN is not set" do
      System.delete_env("GITHUB_TOKEN")

      assert Git.authed_url("https://github.com/example/repo.git") ==
               "https://github.com/example/repo.git"
    end

    test "leaves non-https URLs (e.g. SSH remotes) unchanged even with a token set" do
      System.put_env("GITHUB_TOKEN", "ghp_fake_token")

      assert Git.authed_url("git@github.com:example/repo.git") ==
               "git@github.com:example/repo.git"
    end
  end

  # End-to-end coverage of pull/push against a real project's disk layout
  # (Projects.Disk-managed local bare-repo remotes) lives in
  # projects_test.exs — those tests run with no GITHUB_TOKEN set, which
  # exercises Git.push/2's non-token branch. Since none of those remotes
  # are https:// URLs, authed_url/1's rewrite never fires either way, so
  # there's nothing more to prove end-to-end here without a real GitHub
  # remote; the unit tests above cover the security-sensitive rewrite
  # logic in isolation.
end
