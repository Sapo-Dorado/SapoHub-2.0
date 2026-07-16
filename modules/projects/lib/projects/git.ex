defmodule Projects.Git do
  @moduledoc """
  Git clone/pull/push mechanics, ported from v1's `GitManager`. Shells out to
  the system `git` binary — same assumption v1 made (no extra deps beyond
  `:sapo_module_kit` allowed, so this can't reach for a git library).

  Authenticated pushes/clones reuse the SAME `GITHUB_TOKEN` secret core
  already defines for `sapohub-deploy` (see `nix/nixos-module.nix` and
  `nix/deploy-script.nix`) — it's set in the service's `EnvironmentFile`,
  so it's already present in this app's own environment; no new secret
  plumbing needed. Mirrors `deploy-script.nix`'s exact approach: build a
  one-off `https://x-access-token:$GITHUB_TOKEN@...` URL and pass it only
  as the explicit push/clone target, never persisted into `.git/config` or
  `git remote -v` output. Optional — with no token set, public HTTPS
  clone/pull/commit still work exactly as before; only pushes and private
  clones need it, same degrade-gracefully behavior as the deploy path.
  Commit identity (needed by `initialize_if_empty/1`'s README commit, or
  by anything else run in this checkout that authors a commit — a human
  or assistant session at the shell, say) comes from the ambient
  `/etc/gitconfig` the NixOS module writes from
  `services.sapohub.gitIdentity` — see `nix/nixos-module.nix`. Nothing
  here overrides it with its own `-c user.name=...`/`-c user.email=...`
  anymore; that would just be a second, easy-to-drift place naming the
  same identity.
  """

  alias Projects.Disk

  @doc """
  Clones `github_url` into `source_path(name)`. Returns `{:ok, output}` or
  `{:error, reason}`.

  Clones over an authenticated URL (needed for private repos) but then
  points `origin` back at the bare `github_url` — otherwise the token
  ends up persisted in `.git/config` (readable via `git remote -v`) and
  every later `push/1` re-wraps that already-authenticated URL through
  `authed_url/1` again, producing a doubly-credentialed URL that git
  rejects outright.
  """
  def clone(name, github_url) do
    source = Disk.source_path(name)

    with {:ok, _} <- File.rm_rf(source),
         {:ok, output} <- run_git(Disk.project_root(name), ["clone", authed_url(github_url), "source"]),
         {:ok, _} <- run_git(source, ["remote", "set-url", "origin", github_url]) do
      {:ok, output}
    else
      {:error, reason, _path} -> {:error, "Failed to remove source dir: #{reason}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  If the repo has no commits (e.g. freshly created empty GitHub repo), creates an
  initial README.md commit and pushes it so the repo has a proper default branch.
  Returns `{:ok, :initialized}`, `{:ok, :not_empty}`, or `{:error, reason}`.
  """
  def initialize_if_empty(name) do
    source = Disk.source_path(name)

    case run_git(source, ["rev-parse", "HEAD"]) do
      {:ok, _} ->
        {:ok, :not_empty}

      {:error, _} ->
        readme_path = Path.join(source, "README.md")

        with :ok <- File.write(readme_path, "# #{name}\n"),
             {:ok, _} <- run_git(source, ["add", "README.md"]),
             {:ok, _} <- run_git(source, ["commit", "-m", "Initial commit"]),
             {:ok, _} <- push(source, ["-u", "origin", "HEAD"]) do
          {:ok, :initialized}
        end
    end
  end

  @doc """
  Syncs with remote: checks the working directory is clean, fetches, pushes any
  local commits, then merges remote changes. Returns `{:ok, output}` or
  `{:error, reason}`.
  """
  def pull(name) do
    source = Disk.source_path(name)

    with {:ok, _} <- check_clean(source),
         {:ok, _} <- run_git(source, ["fetch", "origin"]),
         {:ok, ahead, behind} <- commit_counts(source),
         {:ok, _} <- push_if_ahead(source, ahead),
         {:ok, output} <- merge_if_behind(source, behind) do
      Disk.sync_guide()
      {:ok, output}
    end
  end

  @doc """
  Pushes any local commits ahead of the remote. Unlike `pull/1`, this never
  touches the working tree, so it does NOT require (or even check) a clean
  working directory first — uncommitted local changes are simply left
  alone. This is what lets an assistant session with work-in-progress
  still land already-committed commits without being forced to stash or
  finish that work first (the "Pull" button's full `pull/1` flow is a
  fetch+merge too, which DOES need a clean tree to be safe). Returns
  `{:ok, output}` or `{:error, reason}`.
  """
  def push(name) do
    source = Disk.source_path(name)
    push(source, [])
  end

  @doc """
  Checks whether it is safe to delete a project's source directory.
  Returns `{:ok, :safe}` or `{:error, reason}`. Safe if `source/` doesn't
  exist at all (e.g. a failed clone).
  """
  def safe_to_delete?(name) do
    source = Disk.source_path(name)

    if not File.exists?(source) do
      {:ok, :safe}
    else
      case run_git(source, ["status", "--porcelain"]) do
        {:ok, ""} ->
          case run_git(source, ["log", "@{u}..HEAD", "--oneline"]) do
            {:ok, ""} -> {:ok, :safe}
            {:ok, _} -> {:error, "there are unpushed commits"}
            # no upstream configured
            {:error, _} -> {:ok, :safe}
          end

        {:ok, _} ->
          {:error, "there are uncommitted changes"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Returns `{ahead, behind}` relative to the upstream tracking branch.
  # Falls back to `{0, 0}` if no upstream is configured (e.g. detached HEAD).
  defp commit_counts(source) do
    case run_git(source, ["rev-list", "--left-right", "--count", "HEAD...@{u}"]) do
      {:ok, output} ->
        case output |> String.trim() |> String.split("\t") do
          [a, b] -> {:ok, String.to_integer(a), String.to_integer(b)}
          _ -> {:ok, 0, 0}
        end

      {:error, _} ->
        {:ok, 0, 0}
    end
  end

  defp check_clean(source) do
    case run_git(source, ["status", "--porcelain"]) do
      {:ok, ""} -> {:ok, :clean}
      {:ok, _} -> {:error, "Working directory has uncommitted changes — commit or stash them before syncing"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp push_if_ahead(_source, 0), do: {:ok, :nothing_to_push}

  defp push_if_ahead(source, _ahead) do
    case push(source, []) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, "Push failed: #{reason}"}
    end
  end

  # Pushes over an authenticated URL built just for this one push when
  # GITHUB_TOKEN is set — never written to .git/config, never visible in
  # `git remote -v`. Falls back to a bare `git push` (relying on ambient
  # git config/credential helper, if any) when no token is set, exactly
  # like `deploy-script.nix`'s own push step.
  defp push(source, extra_args) do
    case System.get_env("GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        case run_git(source, ["remote", "get-url", "origin"]) do
          {:ok, remote_url} ->
            run_git(source, ["push", authed_url(String.trim(remote_url)) | extra_args])

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        run_git(source, ["push" | extra_args])
    end
  end

  # Rewrites an `https://` remote URL to embed an `x-access-token`
  # credential from GITHUB_TOKEN, matching deploy-script.nix's approach
  # exactly. Non-HTTPS URLs (e.g. git@github.com: SSH remotes) are
  # returned unchanged — there's no token-based auth to add there.
  @doc false
  def authed_url(url) do
    case System.get_env("GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        if String.starts_with?(url, "https://") do
          String.replace(url, "https://", "https://x-access-token:#{token}@", global: false)
        else
          url
        end

      _ ->
        url
    end
  end

  defp merge_if_behind(_source, 0), do: {:ok, "Already up to date."}

  defp merge_if_behind(source, _behind) do
    case run_git(source, ["merge", "@{u}"]) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, "Merge failed: #{reason}"}
    end
  end

  defp run_git(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, scrub(output)}
      {output, _code} -> {:error, scrub(output)}
    end
  end

  # Belt-and-suspenders: modern git already redacts credentials embedded
  # in a URL when it prints one back (e.g. clone/push error output), but
  # that's not something this module should rely on — scrub any literal
  # occurrence of the token out of everything git hands back to us,
  # since this output can end up in API responses and live-streamed
  # script/sync output (Projects.Runner), not just logs.
  defp scrub(output) do
    case System.get_env("GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        String.replace(output, token, "***")

      _ ->
        output
    end
  end
end
