defmodule Mix.Tasks.Sapo.Gen.CliTest do
  use ExUnit.Case, async: false

  test "assembles core + module fragments into an executable script" do
    Mix.Task.rerun("sapo.gen.cli")

    dest = Path.join(Mix.Project.build_path(), "sapo")
    assert File.exists?(dest)

    stat = File.stat!(dest)
    assert Bitwise.band(stat.mode, 0o111) != 0, "script must be executable"

    script = File.read!(dest)

    # Core dispatcher + commands.
    assert script =~ "sapo_main() {"
    assert script =~ "sapo_cmd_context()"
    assert script =~ "sapo_cmd_notify()"
    assert script =~ "sapo_cmd_storage()"

    # Hello module fragment included.
    assert script =~ "sapo_cmd_hello()"

    # Dispatch is the last line so all fragments are defined first.
    assert String.trim(script) |> String.ends_with?("sapo_main \"$@\"")

    # And bash agrees it is syntactically valid.
    {_out, exit_code} = System.cmd("bash", ["-n", dest], stderr_to_stdout: true)
    assert exit_code == 0
  end

  test "composed --help lists core and module resources" do
    Mix.Task.rerun("sapo.gen.cli")
    dest = Path.join(Mix.Project.build_path(), "sapo")

    {out, 0} = System.cmd("bash", [dest, "--help"], stderr_to_stdout: true)

    assert out =~ "Usage: sapo <resource>"
    assert out =~ "notify"
    assert out =~ "storage"
    assert out =~ "hello"
  end
end
