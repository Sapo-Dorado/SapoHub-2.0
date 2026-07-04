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
    machine context (API reference, utilities, current state) from
    GET /api/claude-context. When you finish a task or need user input,
    call `sapo notify "<short message>"` — suppression is handled
    automatically via SAPO_SESSION_ID.
    """
    |> String.trim()
  end
end
