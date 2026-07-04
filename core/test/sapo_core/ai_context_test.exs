defmodule SapoCore.AiContextTest do
  # DataCase: module ai_context fragments may query the DB for live counts.
  use SapoCore.DataCase, async: false

  alias SapoCore.AiContext

  test "contains system info with the endpoint URL" do
    context = AiContext.global_context()

    assert context =~ "# SapoHub AI Context"
    assert context =~ SapoCoreWeb.Endpoint.url()
    assert context =~ SapoCoreWeb.Endpoint.url() <> "/api"
  end

  test "embeds each enabled module's ai_context fragment" do
    context = AiContext.global_context()

    # Hello module section header + its live fragment.
    assert context =~ "### Hello (`sapo_hello`"
    assert context =~ "reference module"
  end

  test "lists all API routes via router introspection" do
    context = AiContext.global_context()

    # Core services and module routes, discovered — never hand-listed.
    assert context =~ "- GET /api/claude-context"
    assert context =~ "- POST /api/notify"
    assert context =~ "- GET /api/storage/files"
    assert context =~ "- GET /api/hello"
    assert context =~ "- DELETE /api/hello/:id"
  end

  test "includes agent notes from config, one bullet per line" do
    previous = Application.get_env(:sapo_core, :agent_notes)
    Application.put_env(:sapo_core, :agent_notes, "First note\nSecond note")

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:sapo_core, :agent_notes)
        val -> Application.put_env(:sapo_core, :agent_notes, val)
      end
    end)

    context = AiContext.global_context()
    assert context =~ "- First note"
    assert context =~ "- Second note"
  end

  test "degrades gracefully when the sapo CLI is absent" do
    # test env has no sapo_cli_path configured and no sapo on PATH inside
    # the test runner — the section must still render.
    assert AiContext.global_context() =~ "CLI Reference"
  end
end
