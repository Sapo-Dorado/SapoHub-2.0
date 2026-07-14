defmodule Projects.ScriptCommand do
  @moduledoc """
  Builds `{cmd, args, env, cwd}` for running a parsed (non-sudo) script.

  Unlike v1's `ScriptCommand`, this module never builds a `sudo` invocation.
  v1 ran sudo scripts through an interactive password-gated LiveView flow
  backed by a local app-user/password table and `/run/wrappers/bin/sudo`.
  v2 has neither an auth system nor any general-purpose root escalation
  (the only sudoers grant in the whole system is the single fixed
  `sapohub-deploy` command) — see the module's `@moduledoc` and the
  migration report for why that gap is deliberately NOT papered over here.
  Callers must check `script.sudo` themselves before calling `build/2`.
  """

  @doc """
  Builds the command tuple for a parsed, non-sudo script.

  `script` is a map from `ScriptParser` (keys: `:file`, `:sudo`, ...)
  optionally extended with `:params_values` (runtime param values, string map).
  `project_root` is the project's root directory on disk (its `source/`
  subdirectory is used as the working directory).

  Returns `{:ok, {cmd, args, env, cwd}}` or `{:error, :sudo_unsupported}`.
  """
  def build(%{sudo: true}, _project_root), do: {:error, :sudo_unsupported}

  def build(script, project_root) do
    bash = System.find_executable("bash") || raise "bash not found on PATH"
    cwd = Path.join(project_root, "source")

    env =
      script
      |> Map.get(:params_values, %{})
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    {:ok, {bash, [script.file], env, cwd}}
  end
end
