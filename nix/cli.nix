# Assembles the `sapo` CLI: core.sh + core's own generated commands + each
# enabled module's generated commands + optional raw fragment.sh + dispatch.
#
# Mirrors `mix sapo.gen.cli` (the dev-time equivalent, see
# core/lib/mix/tasks/sapo.gen.cli.ex) but driven from Nix: for every
# contributor (core itself, then each module) we auto-detect
# priv/cli/commands.exs (generate bash via SapoCliGen.generate/1, run
# through `elixir` at build time) and priv/cli/fragment.sh (raw escape
# hatch, concatenated as-is) by their actual presence on disk rather than
# trusting a hand-set flag — a module contributes whatever combination of
# the two files it happens to have (including neither).
{ pkgs, lib, elixir }:

{ src        # the SapoHub-2.0 repo
, modules    # module packaging attrsets (commands/fragments read from their src)
, apiBase ? "http://localhost:4000/api"
}:

let
  core = builtins.readFile "${src}/core/priv/cli/core.sh";

  sapoCliGenSrc = "${src}/core/lib/mix/sapo_cli_gen.ex";

  contributors =
    [ { name = "core"; path = "${src}/core"; } ]
    ++ map (m: { name = m.name; path = "${m.src}"; }) modules;

  hasCommands = c: builtins.pathExists "${c.path}/priv/cli/commands.exs";
  hasFragment = c: builtins.pathExists "${c.path}/priv/cli/fragment.sh";

  # Single derivation that runs `elixir` once per contributor that has a
  # commands.exs, writing the generated bash out so it can be read back at
  # eval time. Contributors without commands.exs still get an (empty) file
  # so the readFile below never has to branch on derivation contents.
  generated = pkgs.runCommand "sapo-cli-generated" {
    nativeBuildInputs = [ elixir ];
  } ''
    mkdir -p $out
    ${lib.concatMapStrings (c: ''
      ${if hasCommands c then ''
        elixir -e '
          Code.compile_file("${sapoCliGenSrc}")
          {resources, _binding} = Code.eval_file("${c.path}/priv/cli/commands.exs")
          IO.write(SapoCliGen.generate(resources))
        ' > "$out/${c.name}.sh"
      '' else ''
        : > "$out/${c.name}.sh"
      ''}
    '') contributors}
  '';

  contribution = c:
    builtins.readFile "${generated}/${c.name}.sh"
    + (if hasFragment c then builtins.readFile "${c.path}/priv/cli/fragment.sh" else "");

  coreGenerated = contribution (builtins.head contributors);
  moduleContributions =
    lib.concatMapStringsSep "\n" contribution (builtins.tail contributors);

in pkgs.writeShellScriptBin "sapo" ''
  export SAPO_API_BASE="''${SAPO_API_BASE:-${apiBase}}"
  export PATH="${lib.makeBinPath [ pkgs.curl pkgs.jq ]}:$PATH"

  ${core}

  ${coreGenerated}

  ${moduleContributions}

  sapo_main "$@"
''
