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
    * agent notes from the nix option `agentNotes` (AGENT_NOTES env)
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
    - Times are UTC. Convert to the user's timezone for display.
    - When you finish a task or need user input, run `sapo notify "<short message>"` —
      per-session suppression is handled automatically via SAPO_SESSION_ID.
    - Files written under a utility's storage directory appear in the
      storage API and in snapshots automatically.
    #{agent_notes()}
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

  defp agent_notes do
    case Application.get_env(:sapo_core, :agent_notes) do
      notes when is_binary(notes) and notes != "" ->
        notes |> String.split("\n", trim: true) |> Enum.map_join("\n", &"- #{&1}")

      _ ->
        ""
    end
  end
end
