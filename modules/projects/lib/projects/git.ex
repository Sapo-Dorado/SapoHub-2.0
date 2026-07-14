defmodule Projects.Git do
  @moduledoc """
  Git clone/pull/push mechanics, ported from v1's `GitManager`. Shells out to
  the system `git` binary — same assumption v1 made (no extra deps beyond
  `:sapo_module_kit` allowed, so this can't reach for a git library).

  OPEN QUESTION (not resolved by this migration): v1's `flake.nix` wires a
  per-deployment git commit identity (`user.name`/`user.email`) and GitHub
  SSH authentication (`GIT_SSH_COMMAND` + an HTTPS→SSH `insteadOf` URL
  rewrite) into the systemd service environment, so pushes/clones of private
  repos work out of the box. v2's `nix/nixos-module.nix` has none of this —
  no git identity, no SSH key wiring, no URL rewrite. As shipped, this module
  will happily clone/pull public repos over HTTPS and commit locally (using
  whatever ambient git config the host happens to have, or none), but it has
  no declared way to authenticate pushes or clone private repos in a real
  deployment. What identity to bake in and how to supply SSH credentials
  declaratively is a scope decision for the user, not something this
  migration should guess at.
  """

  alias Projects.Disk

  @doc "Clones `github_url` into `source_path(name)`. Returns `{:ok, output}` or `{:error, reason}`."
  def clone(name, github_url) do
    source = Disk.source_path(name)

    with {:ok, _} <- File.rm_rf(source) do
      run_git(Disk.project_root(name), ["clone", github_url, "source"])
    else
      {:error, reason, _path} -> {:error, "Failed to remove source dir: #{reason}"}
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
             {:ok, _} <- run_git(source, ["push", "-u", "origin", "HEAD"]) do
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
    case run_git(source, ["push"]) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, "Push failed: #{reason}"}
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
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, output}
    end
  end
end
