defmodule SapoCliGenTest do
  use ExUnit.Case, async: true

  test "optional param without clear_value just omits the field when empty" do
    resources = [
      %{
        name: "widgets",
        actions: [
          %{
            action: "edit",
            verb: :update,
            path: "/widgets/:id",
            params: [%{key: :title, flag: "--title"}]
          }
        ]
      }
    ]

    script = SapoCliGen.generate(resources)

    assert script =~ ~s|(if $title != "" then {title: $title} else {} end)|
    refute script =~ "null"
  end

  test "clear_value param sends an explicit null when the flag matches the sentinel" do
    resources = [
      %{
        name: "widgets",
        actions: [
          %{
            action: "edit",
            verb: :update,
            path: "/widgets/:id",
            params: [%{key: :due_date, flag: "--due", clear_value: "none"}]
          }
        ]
      }
    ]

    script = SapoCliGen.generate(resources)

    assert script =~
             ~s|(if $due_date == "none" then {due_date: null} elif $due_date != "" then {due_date: $due_date} else {} end)|
  end

  test "bash syntax stays valid with a clear_value param mixed in" do
    resources = [
      %{
        name: "tasks",
        actions: [
          %{
            action: "edit",
            verb: :update,
            path: "/tasks/:id",
            params: [
              %{key: :title, flag: "--title"},
              %{key: :due_date, flag: "--due", clear_value: "none"}
            ]
          }
        ]
      }
    ]

    script = SapoCliGen.generate(resources)
    path = Path.join(System.tmp_dir!(), "sapo_cli_gen_test_#{System.unique_integer([:positive])}.sh")
    File.write!(path, script)

    {_out, exit_code} = System.cmd("bash", ["-n", path], stderr_to_stdout: true)
    File.rm!(path)

    assert exit_code == 0
  end
end
