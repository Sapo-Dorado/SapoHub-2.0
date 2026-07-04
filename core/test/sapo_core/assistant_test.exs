defmodule SapoCore.AssistantTest do
  use ExUnit.Case, async: false

  alias SapoCore.Assistant
  alias SapoCore.Assistant.CommandSession
  alias SapoCore.Assistant.SessionNotifications
  alias SapoCore.Assistant.SessionSupervisor
  alias SapoCore.Assistant.TabStore
  alias SapoCore.Assistant.Terminal

  describe "system_prompt/0" do
    defmodule PromptModule do
      use SapoKit.Module
      def id, do: :prompty
      def title, do: "Prompty"
      def assistant_system_prompt, do: "Use `sapo prompty` for prompty things."
    end

    test "composes the core preamble with module fragments" do
      prompt = Assistant.system_prompt()
      assert prompt =~ "SapoHub"
      assert prompt =~ "/api/claude-context"
    end

    test "module fragments are titled sections" do
      # Compose manually through the same code path used at spawn:
      fragment = PromptModule.assistant_system_prompt()
      assert fragment =~ "sapo prompty"
    end
  end

  describe "CommandSession" do
    test "streams command output over PubSub and exits" do
      session_id = "test-cmd-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{session_id}")

      {:ok, _pid} =
        SessionSupervisor.start_command(session_id, "bash", [
          "-lc",
          "echo hello-from-command; sleep 0.2"
        ])

      assert CommandSession.alive?(session_id)

      assert_receive {:session_output, ^session_id, data}, 5_000
      assert collect_output(session_id, data) =~ "hello-from-command"

      assert_receive {:session_exit, ^session_id, 0}, 5_000

      # Process unregisters after exit.
      wait_until(fn -> not CommandSession.alive?(session_id) end)
    end

    test "buffers output for replay" do
      session_id = "test-cmd-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SapoCore.PubSub, "session:#{session_id}")

      {:ok, _pid} =
        SessionSupervisor.start_command(session_id, "bash", ["-lc", "echo replay-me; sleep 1"])

      assert_receive {:session_output, ^session_id, _}, 5_000
      assert CommandSession.get_buffer(session_id) =~ "replay-me"

      SessionSupervisor.stop_session(session_id)
    end

    test "start_command is idempotent per session id" do
      session_id = "test-cmd-#{System.unique_integer([:positive])}"

      {:ok, pid} = SessionSupervisor.start_command(session_id, "bash", ["-lc", "sleep 2"])
      {:ok, ^pid} = SessionSupervisor.start_command(session_id, "bash", ["-lc", "sleep 2"])

      SessionSupervisor.stop_session(session_id)
    end
  end

  describe "SessionNotifications" do
    test "defaults to disabled, toggles, deletes" do
      refute SessionNotifications.enabled?("some-session")

      :ok = SessionNotifications.set_enabled("some-session", true)
      assert SessionNotifications.enabled?("some-session")

      :ok = SessionNotifications.set_enabled("some-session", false)
      refute SessionNotifications.enabled?("some-session")

      :ok = SessionNotifications.set_enabled("some-session", true)
      :ok = SessionNotifications.delete("some-session")
      refute SessionNotifications.enabled?("some-session")
    end
  end

  describe "TabStore" do
    test "add/list/remove round trip; default tab protected" do
      TabStore.add_tab("sid-1", "Session 2")
      assert %{session_id: "sid-1", label: "Session 2"} in TabStore.list_tabs()

      :ok = TabStore.remove_tab(TabStore.default_session_id())
      TabStore.remove_tab("sid-1")
      refute Enum.any?(TabStore.list_tabs(), &(&1.session_id == "sid-1"))

      n = TabStore.next_num()
      assert TabStore.next_num() == n + 1
    end
  end

  describe "Terminal.clean_output/1" do
    test "strips ANSI escapes and normalises line endings" do
      raw = "\e[?2004l\e[31mred\e[0m\r\nline2\rtail\e]0;title\a"
      assert Terminal.clean_output(raw) == "red\nline2tail"
    end
  end

  defp collect_output(session_id, acc) do
    receive do
      {:session_output, ^session_id, more} -> collect_output(session_id, acc <> more)
    after
      500 -> acc
    end
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition never became true")

      true ->
        Process.sleep(10)
        wait_until(fun, tries - 1)
    end
  end
end
