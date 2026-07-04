defmodule Mix.Tasks.Sapo.Gen.Cli do
  @shortdoc "Assemble the sapo CLI from core + enabled module fragments"

  @moduledoc """
  Concatenates `priv/cli/core.sh` with each enabled module's
  `priv/cli/fragment.sh` (from the modules lock file) and a final dispatch
  line into an executable `sapo` script.

      mix sapo.gen.cli            # writes _build/<env>/sapo

  In releases, nix/cli.nix performs the same assembly into a
  `writeShellScriptBin` (M6); this task is the dev equivalent.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    lock =
      System.get_env(
        "SAPOHUB_MODULES_LOCK",
        Path.join(File.cwd!(), "config/modules.lock.exs")
      )

    {modules, _binding} = Code.eval_file(lock)

    fragments =
      for {app, path} <- modules,
          fragment_path =
            Path.expand(Path.join(path, "priv/cli/fragment.sh"), Path.dirname(lock)),
          File.exists?(fragment_path) do
        {app, File.read!(fragment_path)}
      end

    core = File.read!(Path.join(File.cwd!(), "priv/cli/core.sh"))

    script =
      [core | Enum.map(fragments, &elem(&1, 1))]
      |> Enum.join("\n")
      |> Kernel.<>("\nsapo_main \"$@\"\n")

    dest = Path.join(Mix.Project.build_path(), "sapo")
    File.write!(dest, script)
    File.chmod!(dest, 0o755)

    Mix.shell().info(
      "sapo CLI written to #{dest} " <>
        "(#{length(fragments)} module fragment(s): #{Enum.map_join(fragments, ", ", &elem(&1, 0))})"
    )
  end
end
