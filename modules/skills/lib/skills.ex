defmodule Skills do
  @moduledoc """
  Context for the skills module: tracks which Claude Code skills are
  installed, in two flavors.

    * **marketplace** — a Claude Code plugin (`name@marketplace`), managed
      by shelling out to `claude plugin install|enable|uninstall|details`
      (see `Skills.Application`/`nix/nixos-module.nix` for why `claude` is
      always on this service's PATH with `$HOME` resolved).
    * **custom** — a folder under this module's storage `custom/<name>/`
      directory (SKILL.md + any supporting files), authored directly by
      the assistant or a human with normal file tools. `~/.claude/skills`
      is kept as a standing symlink to that `custom/` directory (see
      `reconcile!/0`), so every folder there is immediately live in Claude
      with no separate install/copy step.

  Once this module is enabled, its own DB (not
  `services.sapohub.assistant.claudeDefaults.user.enabledPlugins`) is the
  sole source of truth for which marketplace plugins are enabled —
  `reconcile!/0` runs at every app boot and forces real Claude state to
  match it exactly.
  """

  import Ecto.Query
  require Logger

  alias Skills.Skill
  alias SapoKit.Repo

  @default_marketplace "claude-plugins-official"

  def list_skills do
    Repo.all(from s in Skill, order_by: [asc: s.name])
  end

  def get_skill!(id), do: Repo.get!(Skill, id)

  @doc "Installs+enables a marketplace plugin and starts tracking it."
  def add_marketplace_skill(name, marketplace \\ @default_marketplace) do
    case run_claude(["plugin", "install", full_name(name, marketplace), "-s", "user"]) do
      {:ok, _output} ->
        %Skill{}
        |> Skill.changeset(%{name: name, kind: "marketplace", marketplace: marketplace})
        |> Repo.insert()

      {:error, output} ->
        {:error, output}
    end
  end

  @doc """
  Registers a custom skill already authored as a folder under this
  module's storage `custom/<name>/SKILL.md` — the standing symlink (see
  `reconcile!/0`) already makes it live in Claude, this just starts
  tracking it.
  """
  def register_custom_skill(name) do
    if File.regular?(SapoKit.Storage.path(:skills, "custom/#{name}/SKILL.md")) do
      %Skill{}
      |> Skill.changeset(%{name: name, kind: "custom"})
      |> Repo.insert()
    else
      {:error, :not_found}
    end
  end

  @doc "Uninstalls/removes a skill and stops tracking it."
  def delete_skill(%Skill{kind: "marketplace"} = skill) do
    run_claude(["plugin", "uninstall", full_name(skill.name, skill.marketplace), "-s", "user", "-y"])
    Repo.delete(skill)
  end

  def delete_skill(%Skill{kind: "custom"} = skill) do
    File.rm_rf!(SapoKit.Storage.path(:skills, "custom/#{skill.name}"))
    Repo.delete(skill)
  end

  @doc "Read-only detail shown by the UI/API viewer."
  def skill_detail(%Skill{kind: "custom"} = skill) do
    File.read(SapoKit.Storage.path(:skills, "custom/#{skill.name}/SKILL.md"))
  end

  def skill_detail(%Skill{kind: "marketplace"} = skill) do
    run_claude(["plugin", "details", full_name(skill.name, skill.marketplace)])
  end

  # ── Boot-time reconciliation ─────────────────────────────────────────────

  @doc """
  Run once at every app boot (see `Skills.Module.children/1`):

    1. Ensures `~/.claude/skills` is a symlink to this module's storage
       `custom/` dir, so every registered custom skill folder is
       immediately live.
    2. One-time seed of whatever marketplace plugins were already
       installed before this module first ran (so nothing already-enabled
       is silently dropped the first time it boots).
    3. Full-ownership sync: forces the real set of installed/enabled
       marketplace plugins to match this module's tracked rows exactly —
       installing/enabling what's missing, uninstalling anything present
       that isn't tracked.

  Best-effort throughout: logs and moves on rather than crashing the boot
  task on an individual `claude` command failure.
  """
  def reconcile! do
    ensure_skills_symlink()
    maybe_seed_from_existing_installs()
    sync_marketplace_plugins()
    :ok
  end

  defp ensure_skills_symlink do
    target = Path.join([claude_home(), ".claude", "skills"])
    desired = SapoKit.Storage.path(:skills, "custom")

    File.mkdir_p!(desired)
    File.mkdir_p!(Path.dirname(target))

    case File.read_link(target) do
      {:ok, ^desired} ->
        :ok

      _ ->
        File.rm_rf!(target)
        File.ln_s!(desired, target)
    end
  end

  defp maybe_seed_from_existing_installs do
    marker = SapoKit.Storage.path(:skills, ".seeded")

    unless File.exists?(marker) do
      installed_user_plugins()
      |> Enum.reject(fn {name, _marketplace} -> Repo.get_by(Skill, name: name) end)
      |> Enum.each(fn {name, marketplace} ->
        %Skill{}
        |> Skill.changeset(%{name: name, kind: "marketplace", marketplace: marketplace})
        |> Repo.insert()
      end)

      File.write!(marker, "")
    end
  end

  defp sync_marketplace_plugins do
    tracked = Repo.all(from s in Skill, where: s.kind == "marketplace")
    desired = MapSet.new(tracked, &full_name(&1.name, &1.marketplace))

    Enum.each(tracked, &ensure_enabled(full_name(&1.name, &1.marketplace)))

    for {name, marketplace} <- installed_user_plugins(),
        full = full_name(name, marketplace),
        not MapSet.member?(desired, full) do
      run_claude(["plugin", "uninstall", full, "-s", "user", "-y"])
    end
  end

  defp ensure_enabled(full) do
    case run_claude(["plugin", "enable", full]) do
      {:ok, _} -> :ok
      {:error, _} -> run_claude(["plugin", "install", full, "-s", "user"])
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp full_name(name, marketplace), do: "#{name}@#{marketplace}"

  # Overridable via `config :skills, claude_home: ...` (see core's
  # config/test.exs) so tests never touch the real box's ~/.claude.
  defp claude_home do
    Application.get_env(:skills, :claude_home) || System.get_env("HOME") || "/var/lib/sapohub"
  end

  # {name, marketplace} pairs for every "scope: user" installed plugin, read
  # from Claude's own install-state file rather than settings.json's
  # enabledPlugins (which only reflects current enable/disable, not what's
  # actually installed/cached — see the moduledoc on why that distinction
  # matters for the one-time seed).
  defp installed_user_plugins do
    path = Path.join([claude_home(), ".claude", "plugins", "installed_plugins.json"])

    with {:ok, contents} <- File.read(path),
         {:ok, %{"plugins" => plugins}} <- Jason.decode(contents) do
      for {full, installs} <- plugins,
          Enum.any?(installs, &(&1["scope"] == "user")),
          String.contains?(full, "@") do
        [name, marketplace] = String.split(full, "@", parts: 2)
        {name, marketplace}
      end
    else
      _ -> []
    end
  end

  # Disabled via `config :skills, enable_claude_cli: false` in tests — no
  # network, deterministic, and never mutates real installed plugins.
  defp run_claude(args) do
    if Application.get_env(:skills, :enable_claude_cli, true) do
      case System.cmd("claude", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, output}

        {output, status} ->
          Logger.warning("skills: `claude #{Enum.join(args, " ")}` exited #{status}: #{output}")
          {:error, output}
      end
    else
      {:ok, ""}
    end
  end
end
