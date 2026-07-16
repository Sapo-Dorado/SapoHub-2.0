defmodule SapoCore.AiContext do
  @moduledoc """
  Generates the live Markdown context document served at
  `GET /api/claude-context` (ported from v1, minus hard-coded URLs).

  Composition:

    * base/API URL from `Endpoint.url()` (nix decides the real host)
    * per-module `ai_context/0` fragments — modules embed their own live
      counts, so core never reaches into module data
    * CLI reference by shelling out to `sapo --help` (omitted if absent)
    * API reference via router introspection (always current)
    * fixed "Notes for AI Agents" — framework-level rules true of any
      SapoHub 2.0 deployment. Module-specific guidance doesn't belong here:
      modules contribute their own state/usage via `ai_context/0` (embedded
      above, under Utilities) or behavioral rules for the live embedded
      assistant via `assistant_system_prompt/0` (SapoCore.Assistant).
  """

  alias SapoCore.Generated.Registry

  @doc "The full Markdown context document."
  @spec global_context() :: String.t()
  def global_context do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    base = SapoCoreWeb.Endpoint.url()
    api_base = base <> "/api"

    """
    # SapoHub AI Context
    Generated: #{now}

    ## System
    SapoHub is a personal utility hub running at #{base}
    API base: #{api_base} (no auth required, Tailscale-only)

    ## CLI
    All operations are available as CLI commands via `sapo`.
    Environment: SAPO_API_BASE=#{api_base}
    Run `sapo --help` to see all available commands.

    ## Utilities
    #{utilities_section()}

    ## CLI Reference

    #{cli_reference()}

    ## API Reference
    Base: #{api_base} — no auth required.
    All request bodies use Content-Type: application/json.
    All IDs are UUIDs. Dates are YYYY-MM-DD. Datetimes are ISO8601 UTC.

    #{api_routes()}

    ## Notes for AI Agents
    - The database always stores/queries UTC. The API returns UTC.
      #{display_timezone_note()}
    - SapoHub 2.0 modules are independent — anything shared across modules
      (notify, storage, scheduling, HTTP) goes through SapoKit.* facades,
      not direct module-to-module calls.
    - The app runs without root except one sudo command: `sapohub-deploy`.
      Other sudo commands are blocked at the system level — don't attempt them.
    - The `sapo` CLI is the preferred interface over raw curl calls. Module
      commands appear automatically once a module ships
      `priv/cli/commands.exs` (see docs/module-authoring.md) — no manual
      wiring needed.
    - Never trigger a deploy without explicit user instruction — it rebuilds
      and restarts the live service. Always ensure changes are committed AND
      pushed first (deploys pull from git, not the local working copy).
    - Plain `sapohub-deploy` (no flags) doesn't need GITHUB_TOKEN. That
      secret is only required for `--sync-prefs` (what the Settings page's
      Deploy button runs), which also pushes a UI-prefs commit back to the
      config repo.
    - Before committing, run `git fetch origin` then
      `git log HEAD..origin/main --oneline` — rebase first if it returns commits.
    - Ambient git identity (system-wide /etc/gitconfig, services.sapohub.
      gitIdentity) is already set up — plain `git commit` works with no
      identity flags needed. To push a commit in a Projects-module checkout
      (e.g. this repo itself), use `sapo projects push <id>` — it pushes
      whatever's committed without touching the working tree, unlike
      `sapo projects sync <id>` (fetch+push+merge) which requires a fully
      clean tree first. GITHUB_TOKEN itself is root-only and never readable
      here — these operations authenticate inside the app process, not via
      any credential this session has direct access to.
    - The live system config — what the Settings page's Deploy button
      actually rebuilds from (host options, services.sapohub.* settings,
      prefs, secrets file paths, disko/hardware config, etc.) — is a
      SEPARATE git repo from this SapoHub-2.0 source tree. The on-disk
      checkout at services.sapohub.deploy.flakePath (default
      /etc/sapohub-config) is what `sapohub-deploy` itself rebuilds from,
      but it's root-owned and not the checkout to edit from an assistant
      session — edit it via its Projects-module entry instead (add one
      with `sapo projects create <name> <its-github-url>` if it isn't
      already there) and use the same `sapo projects push`/`sync` tooling
      described above. To find/confirm which repo it is: `cat
      /etc/sapohub-config/flake.nix` (or `git -C /etc/sapohub-config
      remote get-url origin` for its GitHub URL — also visible as
      services.sapohub.deploy.repoUrl in whatever flake built this box, or
      via `systemctl cat sapohub-config-clone`), then match that URL
      against `sapo projects list`. Editing it does NOT apply anything by
      itself — it still takes a `sapohub-deploy` run (manual, or the
      Settings Deploy button) to rebuild and restart the live system from
      whatever's committed there, per the deploy rule above.
    - Files written under a module's storage directory appear in the
      storage API and in snapshots automatically — no manual registration needed.
    """
  end

  # ── Sections ───────────────────────────────────────────────────────────────

  defp utilities_section do
    Registry.modules()
    |> Enum.map_join("\n\n", fn mod ->
      header = "### #{mod.title()} (`#{mod.id()}`, v#{mod.version()})"

      case safe_fragment(mod) do
        nil -> header
        fragment -> header <> "\n" <> String.trim(fragment)
      end
    end)
    |> case do
      "" -> "(no utilities enabled)"
      section -> section
    end
  end

  defp safe_fragment(mod) do
    mod.ai_context()
  rescue
    _ -> nil
  end

  defp cli_reference do
    case sapo_executable() do
      nil ->
        "(sapo CLI not available in this environment)"

      sapo ->
        {output, _} = System.cmd(sapo, ["--help"], stderr_to_stdout: true)
        String.trim(output)
    end
  rescue
    _ -> "(sapo CLI not available in this environment)"
  end

  defp sapo_executable do
    configured = Application.get_env(:sapo_core, :sapo_cli_path)

    cond do
      is_binary(configured) and File.exists?(configured) -> configured
      sapo = System.find_executable("sapo") -> sapo
      true -> nil
    end
  end

  # Router introspection: the API list stays accurate without manual updates.
  defp api_routes do
    SapoCoreWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.filter(&String.starts_with?(&1.path, "/api"))
    |> Enum.sort_by(&{&1.path, &1.verb})
    |> Enum.map_join("\n", &"- #{String.upcase(to_string(&1.verb))} #{&1.path}")
  end

  defp display_timezone_note do
    case SapoCore.Time.display_timezone() do
      "Etc/UTC" ->
        "The UI also displays times in UTC (services.sapohub.timezone is unset/default)."

      tz ->
        "The UI displays times in #{tz} (services.sapohub.timezone) — convert accordingly if quoting a time back to the user."
    end
  end
end
