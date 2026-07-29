# Builds the llama-swap package + renders its YAML config from
# services.sapohub.assistant.localModels.{models,groups}. Consumed by
# nixos-module.nix, which defines the actual systemd unit and env wiring —
# this file only produces the pieces that unit needs.
#
# `groups` (llama-swap's concurrent-warm-set feature) is intentionally NOT
# rendered here yet: current llama-swap (v244+) replaced the simple
# swap/members `groups:` key with a solver-based `matrix:` DSL, and the exact
# translation from this module's simpler `groups` option hasn't been verified
# against that DSL. nixos-module.nix asserts `groups == {}` until that's done.
{ pkgs, lib, toolsPkgs }:
{ models }:

let
  llamaCpp = toolsPkgs.llama-cpp;

  yamlFormat = pkgs.formats.yaml { };

  # ${PORT} is llama-swap's OWN macro (auto-incremented from its startPort,
  # one per model) — passed through as a literal string, not Nix-interpolated.
  renderModel = _name: m:
    {
      cmd = lib.concatStringsSep " " ([
        "${llamaCpp}/bin/llama-server"
        "--model" m.weightsPath
        "--port"
        "\${PORT}"
        "--ctx-size"
        (toString m.contextSize)
      ] ++ m.extraArgs);
    }
    // lib.optionalAttrs (m.ttl != null) { inherit (m) ttl; };

  renderedConfig = {
    models = lib.mapAttrs renderModel models;
  };

  configFile = yamlFormat.generate "llama-swap-config.yaml" renderedConfig;

  # One shell snippet per model that has a `source` set — skipped entirely
  # (empty string) for entries left to manual placement, matching how this
  # module worked before `source` existed. Downloads to a `.partial` sibling
  # and only `mv`s it into place on success, so a killed/interrupted fetch
  # can never be mistaken for a complete file on the next start; `curl
  # --continue-at -` resumes that same partial on retry instead of
  # restarting a multi-GB download from zero.
  fetchSnippet = name: m:
    lib.optionalString (m.source != null) ''
      if [ -f "${m.weightsPath}" ]; then
        echo "local-llm: '${name}' already present at ${m.weightsPath}, skipping fetch"
      else
        echo "local-llm: fetching '${name}' from ${m.source}"
        mkdir -p "$(dirname "${m.weightsPath}")"
        ${pkgs.curl}/bin/curl -fSL --retry 3 --continue-at - \
          -o "${m.weightsPath}.partial" "${m.source}"
        mv "${m.weightsPath}.partial" "${m.weightsPath}"
      fi
    '';

  fetchScript = pkgs.writeShellScript "sapohub-fetch-models" ''
    set -euo pipefail
    ${lib.concatStrings (lib.mapAttrsToList fetchSnippet models)}
  '';
in
{
  package = toolsPkgs.callPackage ./llama-swap.nix { };
  inherit configFile fetchScript;
}
