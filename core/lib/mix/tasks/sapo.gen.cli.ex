defmodule Mix.Tasks.Sapo.Gen.Cli do
  @shortdoc "Assemble the sapo CLI from core + enabled module commands"

  @moduledoc """
  Assembles `priv/cli/core.sh`, each enabled module's generated commands
  (from `priv/cli/commands.exs` — see `SapoCliGen`), and each module's
  optional raw `priv/cli/fragment.sh` escape hatch (from the modules lock
  file), plus a final dispatch line, into an executable `sapo` script.

      mix sapo.gen.cli            # writes _build/<env>/sapo

  In releases, nix/compose.nix runs this same task inside the release build
  (M6) so there is exactly one place commands.exs -> bash codegen happens.
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

    contributions =
      for {app, path} <- modules do
        base = Path.expand(path, Path.dirname(lock))
        commands_path = Path.join(base, "priv/cli/commands.exs")
        fragment_path = Path.join(base, "priv/cli/fragment.sh")

        generated =
          if File.exists?(commands_path) do
            {resources, _binding} = Code.eval_file(commands_path)
            SapoCliGen.generate(resources)
          else
            ""
          end

        raw = if File.exists?(fragment_path), do: File.read!(fragment_path), else: ""

        contributed? = generated != "" or raw != ""
        {app, Enum.join([generated, raw], "\n"), contributed?}
      end
      |> Enum.filter(&elem(&1, 2))

    core = File.read!(Path.join(File.cwd!(), "priv/cli/core.sh"))

    script =
      [core | Enum.map(contributions, &elem(&1, 1))]
      |> Enum.join("\n")
      |> Kernel.<>("\nsapo_main \"$@\"\n")

    dest = Path.join(Mix.Project.build_path(), "sapo")
    File.write!(dest, script)
    File.chmod!(dest, 0o755)

    Mix.shell().info(
      "sapo CLI written to #{dest} " <>
        "(#{length(contributions)} module contribution(s): " <>
        "#{Enum.map_join(contributions, ", ", &elem(&1, 0))})"
    )
  end
end
