# Assembles the `sapo` CLI: core.sh + enabled module fragments + dispatch.
# Mirrors `mix sapo.gen.cli` (the dev-time equivalent).
{ pkgs, lib }:

{ src        # the SapoHub-2.0 repo
, modules    # module packaging attrsets (fragments read from their src)
, apiBase ? "http://localhost:4000/api"
}:

let
  fragments = lib.concatMapStringsSep "\n"
    (m:
      if m.cliFragment or false
      then builtins.readFile "${m.src}/priv/cli/fragment.sh"
      else "")
    modules;

  core = builtins.readFile "${src}/core/priv/cli/core.sh";

in pkgs.writeShellScriptBin "sapo" ''
  export SAPO_API_BASE="''${SAPO_API_BASE:-${apiBase}}"
  export PATH="${lib.makeBinPath [ pkgs.curl pkgs.jq ]}:$PATH"

  ${core}

  ${fragments}

  sapo_main "$@"
''
