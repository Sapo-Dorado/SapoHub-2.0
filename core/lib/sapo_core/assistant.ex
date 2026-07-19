defmodule SapoCore.Assistant do
  @moduledoc """
  The core assistant feature: interactive `claude` sessions in PTYs,
  streamed to the browser over PubSub (see `SapoCore.Assistant.SessionRunner`
  and `AssistantLive`), plus fixed-command PTY sessions for things like the
  Deploy button (`SapoCore.Assistant.CommandSession`).
  """

  alias SapoCore.Generated.Registry

  @doc """
  The system prompt appended to every assistant session
  (`--append-system-prompt`): a short core preamble plus each enabled
  module's `assistant_system_prompt/0` fragment in dependency order.
  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    fragments =
      for mod <- Registry.modules(),
          fragment = mod.assistant_system_prompt(),
          is_binary(fragment) and fragment != "",
          do: "## #{mod.title()}\n\n#{String.trim(fragment)}"

    ([core_preamble() | fragments] ++ [])
    |> Enum.join("\n\n")
  end

  @doc "Working directory for assistant sessions."
  @spec workdir() :: String.t()
  def workdir do
    Application.get_env(:sapo_core, :assistant_workdir) ||
      System.get_env("HOME") ||
      "/tmp"
  end

  defp core_preamble do
    """
    # SapoHub

    You are running inside SapoHub, a personal utility hub. Fetch the full
    machine context (API reference, utilities, current state) by running
    `sapo context` — do NOT curl the /api/claude-context endpoint directly:
    plain `http://localhost/...` hits nginx on port 80, which 301-redirects
    to https and confuses curl. `sapo context` already targets the correct
    address via SAPO_API_BASE (the app listens directly on port 4000, no
    TLS). The same SAPO_API_BASE rule applies to any other endpoint you
    need to hit with raw curl — prefer $SAPO_API_BASE/... over
    http(s)://localhost/api/.... When you finish a task or need user
    input, call `sapo notify "<short message>"` — suppression is handled
    automatically via SAPO_SESSION_ID.

    For `sapo` CLI usage, run `sapo help`, `sapo <resource> help`, or
    `sapo <resource>` with no action — these all print usage. `--help`/`-h`
    placed after an action verb (e.g. `sapo recipes create --help`) is NOT
    recognized as a help flag; it's consumed as a positional argument and
    will create/act on a real record named "--help". Always ask for help
    before the action, never after it.
    """
    |> String.trim()
  end
end
